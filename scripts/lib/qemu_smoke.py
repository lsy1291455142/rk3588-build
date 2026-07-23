#!/usr/bin/env python3
import argparse
import pathlib
import re
import socket
import sys
import time

import pexpect


FATAL_PATTERNS = (
    r"Kernel panic",
    r"\bOops:",
    r"\bBUG:",
    r"Unable to mount root fs",
    r"VFS: Cannot open root device",
    r"No working init found",
    r"Attempted to kill init",
    r"You are in emergency mode",
    r"Entering emergency mode",
    r"Failed to start ",
    r"Dependency failed for ",
)

BOOT_ERROR_PATTERNS = (
    r"\bfailed\b",
    r"\bfailure\b",
    r"\berror\b",
)

SERIAL_LOGIN_MARKER = "__RK3588_SERIAL_LOGIN_OK__"


def parse_args():
    parser = argparse.ArgumentParser(description="Boot and validate a Debian ARM64 image")
    parser.add_argument("--qemu", required=True)
    parser.add_argument("--kernel", required=True)
    parser.add_argument("--disk", required=True)
    parser.add_argument("--kernel-release", required=True)
    parser.add_argument("--debian-release", required=True)
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--initrd", default="")
    parser.add_argument("--rootfs-mode", default="rw-ext4")
    parser.add_argument(
        "--initcall-blacklist",
        default="",
        help="comma-separated initcalls to blacklist under QEMU (from SoC traits)",
    )
    parser.add_argument(
        "--serial-getty-mask",
        default="",
        help="comma-separated serial-getty units to mask under QEMU (from SoC traits)",
    )
    parser.add_argument("--timeout", type=int, required=True)
    parser.add_argument("--memory-mib", type=int, required=True)
    parser.add_argument("--cpus", type=int, required=True)
    parser.add_argument("--serial-log", required=True)
    parser.add_argument("--ssh-log", required=True)
    parser.add_argument("--result", required=True)
    return parser.parse_args()


def reserve_tcp_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def fail(message, child=None):
    if child is not None and child.isalive():
        child.close(force=True)
    raise RuntimeError(message)


def wait_for_login(child, timeout):
    patterns = [r"(?:^|\r?\n)[^\r\n]* login: ?$"] + list(FATAL_PATTERNS)
    index = child.expect(patterns, timeout=timeout)
    if index != 0:
        fail(f"fatal boot message matched: {patterns[index]}", child)


def login_serial(child, username, password):
    child.sendline(username)
    index = child.expect([r"Password:", r"Login incorrect", r" login:"], timeout=60)
    if index != 0:
        fail("serial username was rejected", child)
    child.sendline(password)
    index = child.expect([r"[$#] ", r"Login incorrect", r" login:"], timeout=60)
    if index != 0:
        fail("serial password login failed", child)
    child.sendline("stty -echo")
    child.expect(r"[$#] ", timeout=30)
    child.sendline(f"printf '{SERIAL_LOGIN_MARKER}\\n'")
    index = child.expect(
        [SERIAL_LOGIN_MARKER, r"Login incorrect", r" login:"], timeout=60
    )
    if index != 0:
        fail("serial password login failed", child)


def run_guest_checks(child, kernel_release, debian_release, password, rootfs_mode):
    if rootfs_mode == "ro-overlay":
        # The overlay upper lives on the ext4 data partition, not the read-only
        # SquashFS root; verify the data partition actually came up mounted.
        resize_check = (
            "data_mount",
            "findmnt -n -o TARGET /data >/dev/null 2>&1",
        )
    else:
        resize_check = (
            "root_resize",
            "rootsize=$(df -BM --output=size / | tail -1 | tr -dc '0-9'); "
            "test \"${rootsize:-0}\" -ge 3000",
        )
    commands = [
        ("debian_release", f"grep -Eq '^{debian_release}([.]|$)' /etc/debian_version"),
        ("architecture", "test \"$(uname -m)\" = aarch64"),
        ("kernel_release", f"test \"$(uname -r)\" = '{kernel_release}'"),
        ("root_rw", "findmnt -n -o OPTIONS / | tr ',' '\\n' | grep -qx rw"),
        ("firstboot", "test -e /var/lib/sbc-firstboot.done"),
        resize_check,
        ("systemd_running", "test \"$(systemctl is-system-running 2>/dev/null)\" = running"),
        ("unit_health", "test -z \"$(systemctl --failed --no-legend --plain)\""),
        ("ssh_service", "systemctl is-active --quiet ssh.service"),
        (
            "network_service",
            "systemctl is-active --quiet NetworkManager.service || "
            "systemctl is-active --quiet systemd-networkd.service",
        ),
        ("resolved_service", "systemctl is-active --quiet systemd-resolved.service"),
        ("sshd_config", "/usr/sbin/sshd -t"),
        (
            "ipv4",
            "found=0; for i in $(seq 1 90); do ip -4 -o addr show scope global | "
            "grep -q ' inet ' && { found=1; break; }; sleep 1; done; "
            "test \"$found\" = 1",
        ),
    ]
    child.sendline("sudo -S -p '__RK3588_CHECK_PASSWORD__' /bin/sh")
    child.expect(r"__RK3588_CHECK_PASSWORD__", timeout=30)
    child.sendline(password)
    child.expect(r"# ", timeout=30)

    child.sendline(
        "ready=0; for i in $(seq 1 180); do "
        "if test -e /var/lib/sbc-firstboot.done && "
        "test \"$(systemctl is-system-running 2>/dev/null)\" = running; "
        "then ready=1; break; fi; sleep 1; done; "
        "printf '__RK3588_BOOT_READY__=%s\\n' \"$ready\""
    )
    child.expect(r"__RK3588_BOOT_READY__=([0-9]+)", timeout=210)
    if child.match.group(1) != "1":
        fail("Debian did not finish first boot with systemd running", child)

    failed_checks = []
    for name, command in commands:
        child.sendline(
            f"if {{ {command}; }}; then result=0; else result=1; fi; "
            f"printf '__RK3588_CHECK_{name}__=%s\\n' \"$result\""
        )
        child.expect(rf"__RK3588_CHECK_{name}__=([0-9]+)", timeout=120)
        if child.match.group(1) != "0":
            failed_checks.append(name)
    if failed_checks:
        fail(f"Debian guest checks failed: {', '.join(failed_checks)}", child)
    child.sendline("exit")
    child.expect(r"[$] ", timeout=30)


def test_ssh(port, username, password, debian_release, ssh_log_path):
    command = "ssh"
    args = [
        "-p",
        str(port),
        "-o",
        "BatchMode=no",
        "-o",
        "ConnectTimeout=30",
        "-o",
        "PreferredAuthentications=password",
        "-o",
        "PubkeyAuthentication=no",
        "-o",
        "StrictHostKeyChecking=no",
        "-o",
        "UserKnownHostsFile=/dev/null",
        f"{username}@127.0.0.1",
        "printf '__RK3588_SSH_OK__'; "
        f"grep -Eq '^{debian_release}([.]|$)' /etc/debian_version",
    ]
    deadline = time.monotonic() + 90
    last_error = "SSH did not become ready"
    while time.monotonic() < deadline:
        with ssh_log_path.open("a", encoding="utf-8") as ssh_log:
            child = pexpect.spawn(
                command,
                args,
                encoding="utf-8",
                codec_errors="replace",
                timeout=35,
            )
            child.logfile_read = ssh_log
            try:
                index = child.expect([r"[Pp]assword:", r"Connection refused", pexpect.EOF])
                if index == 0:
                    child.sendline(password)
                    child.expect(r"__RK3588_SSH_OK__", timeout=30)
                    child.expect(pexpect.EOF, timeout=30)
                    child.close()
                    if child.exitstatus == 0:
                        return
                    last_error = f"SSH command exited with {child.exitstatus}"
                else:
                    last_error = "SSH connection was refused or closed"
            except (pexpect.TIMEOUT, pexpect.EOF) as exc:
                last_error = f"SSH login failed: {exc}"
            finally:
                if child.isalive():
                    child.close(force=True)
        time.sleep(2)
    raise RuntimeError(last_error)


def shutdown_guest(child, password):
    child.sendline("sudo -k")
    child.expect(r"[$] ", timeout=30)
    child.sendline("sudo -S -p '__RK3588_SUDO_PASSWORD__' /sbin/poweroff")
    child.expect(r"__RK3588_SUDO_PASSWORD__", timeout=30)
    child.sendline(password)
    index = child.expect([r"Power down", pexpect.EOF], timeout=120)
    if index == 0:
        child.expect(pexpect.EOF, timeout=30)
    child.close()
    if child.exitstatus not in (0, None):
        raise RuntimeError(f"QEMU exited with status {child.exitstatus}")


def scan_serial_log(serial_log_path):
    contents = serial_log_path.read_text(encoding="utf-8", errors="replace")
    marker_offset = contents.find(SERIAL_LOGIN_MARKER)
    if marker_offset < 0:
        raise RuntimeError("serial log does not contain the successful login marker")
    for pattern in FATAL_PATTERNS + BOOT_ERROR_PATTERNS:
        if re.search(pattern, contents, flags=re.IGNORECASE | re.MULTILINE):
            raise RuntimeError(f"serial log contains error pattern: {pattern}")


def main():
    args = parse_args()
    serial_log_path = pathlib.Path(args.serial_log)
    ssh_log_path = pathlib.Path(args.ssh_log)
    result_path = pathlib.Path(args.result)
    serial_log_path.parent.mkdir(parents=True, exist_ok=True)
    ssh_log_path.write_text("", encoding="utf-8")
    ssh_port = reserve_tcp_port()
    initcall_blacklist = [x for x in args.initcall_blacklist.split(",") if x]
    serial_getty_masks = [x for x in args.serial_getty_mask.split(",") if x]
    mask_args = " ".join(f"systemd.mask={m}" for m in serial_getty_masks)
    common_tail = (
        "console=ttyAMA0,115200 earlycon=pl011,0x09000000 "
        f"initcall_blacklist={','.join(initcall_blacklist)} "
        "systemd.default_device_timeout_sec=300s "
        "systemd.default_timeout_start_sec=300s "
        f"{mask_args} consoleblank=0"
    )
    if args.rootfs_mode == "ro-overlay":
        # Read-only SquashFS root + ext4 data partition assembled by the
        # initramfs overlayroot hook (activated by overlayroot=PARTLABEL=data).
        kernel_args = (
            "root=PARTLABEL=rootfs rootwait ro overlayroot=PARTLABEL=data "
            f"{common_tail}"
        )
    else:
        kernel_args = (
            "root=PARTLABEL=rootfs rootwait rw "
            f"{common_tail}"
        )
    qemu_args = [
        "-machine",
        "virt,gic-version=3",
        "-cpu",
        "max",
        "-smp",
        str(args.cpus),
        "-m",
        str(args.memory_mib),
        "-kernel",
        args.kernel,
        "-append",
        kernel_args,
    ]
    if args.initrd:
        qemu_args += ["-initrd", args.initrd]
    qemu_args += [
        "-drive",
        f"if=none,id=rootdisk,file={args.disk},format=raw,cache=unsafe",
        "-device",
        "virtio-blk-device,drive=rootdisk",
        "-netdev",
        f"user,id=net0,hostfwd=tcp:127.0.0.1:{ssh_port}-:22",
        "-device",
        "virtio-net-device,netdev=net0",
        "-object",
        "rng-random,id=rng0,filename=/dev/urandom",
        "-device",
        "virtio-rng-device,rng=rng0",
        "-nographic",
        "-monitor",
        "none",
        "-no-reboot",
    ]

    try:
        with serial_log_path.open("w", encoding="utf-8") as serial_log:
            child = pexpect.spawn(
                args.qemu,
                qemu_args,
                encoding="utf-8",
                codec_errors="replace",
                timeout=args.timeout,
            )
            child.logfile_read = serial_log
            wait_for_login(child, args.timeout)
            login_serial(child, args.username, args.password)
            run_guest_checks(
                child, args.kernel_release, args.debian_release, args.password,
                args.rootfs_mode,
            )
            test_ssh(
                ssh_port,
                args.username,
                args.password,
                args.debian_release,
                ssh_log_path,
            )
            shutdown_guest(child, args.password)
        scan_serial_log(serial_log_path)
    except (RuntimeError, pexpect.TIMEOUT, pexpect.EOF) as exc:
        print(f"QEMU smoke test failed: {exc}", file=sys.stderr)
        return 1

    result_path.write_text(
        "status=passed\n"
        f"kernel_release={args.kernel_release}\n"
        f"debian_release={args.debian_release}\n"
        "serial_login=passed\n"
        "systemd=running\n"
        "failed_units=0\n"
        "firstboot_resize=passed\n"
        "network=passed\n"
        "ssh_password_login=passed\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
