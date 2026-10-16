#!/usr/bin/env python3
"""Encrypted environment variables; compatible with the original Bash CLI."""

import argparse
import base64
import binascii
import getpass
import hashlib
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import warnings


MAGIC_V1 = b"QSENVENC1"
MAGIC_V2 = b"QSENVENC2"
ENV_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*", re.ASCII)


class SecretError(Exception):
    pass


class MissingPassword(SecretError):
    pass


def encode(text):
    return text.encode("utf-8", errors="surrogateescape")


def decode(data):
    return data.decode("utf-8", errors="surrogateescape")


def validate_name(name):
    if not ENV_NAME.fullmatch(name):
        raise SecretError(f"Invalid env name: {name}")


def parse_env_name(name):
    try:
        validate_name(name)
    except SecretError as error:
        raise argparse.ArgumentTypeError(str(error)) from error
    return name


def password_key(password):
    return hashlib.sha256(encode(password)).hexdigest()


def atomic_write(path, data):
    """Keep replacements on the same filesystem and private from creation."""
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def crypt(data, phrase, decrypt=False):
    # Keep the passphrase out of argv, and plaintext in memory rather than /tmp.
    read_fd, write_fd = os.pipe()
    try:
        with os.fdopen(write_fd, "wb") as stream:
            stream.write(encode(phrase) + b"\n")
        command = ["openssl", "enc", "-aes-256-cbc", "-pbkdf2"]
        command.append("-d" if decrypt else "-salt")
        command.extend(["-pass", f"fd:{read_fd}"])
        try:
            result = subprocess.run(
                command, input=data, capture_output=True, pass_fds=(read_fd,)
            )
        except FileNotFoundError as error:
            raise SecretError("缺少必要依赖: openssl") from error
    finally:
        os.close(read_fd)
    if result.returncode:
        # OpenSSL diagnostics need not be exposed alongside secret operations.
        action = "decrypt" if decrypt else "encrypt"
        raise SecretError(f"Failed to {action} encrypted db. Check password and OpenSSL support.")
    return result.stdout


class SecretEnv:
    def __init__(self):
        home = Path.home()
        dotfiles = Path(os.environ.get("DOTFILES_DIR") or home / ".dotfiles")
        config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
        self.conf_dir = config / "q-secret-env"
        self.legacy_dir = config / "lu5je0/q-secret-env"
        self.pass_file = self.conf_dir / "master.pass"
        self.env_file = self.conf_dir / "env.zsh"
        self.enc_file = dotfiles / "secrets/q-secret-env.enc"

    def ensure_dirs(self):
        self.conf_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.conf_dir.chmod(0o700)
        self.enc_file.parent.mkdir(parents=True, exist_ok=True)
        if self.legacy_dir.is_dir():
            for name in ("master.pass", "env.zsh"):
                source = self.legacy_dir / name
                target = self.conf_dir / name
                if source.is_file() and not target.exists():
                    source.replace(target)
                    target.chmod(0o600)
            try:
                self.legacy_dir.rmdir()
            except OSError:
                pass

    def pass_line(self, read_only=False):
        path = self.pass_file
        if read_only and not path.exists():
            path = self.legacy_dir / "master.pass"
        if not path.exists():
            return ""
        return decode(path.read_bytes().split(b"\n", 1)[0])

    def phrase(self, read_only=False):
        line = self.pass_line(read_only=read_only)
        if line.startswith("QSENV2:"):
            key = line.split(":")[1]
            if key:
                return f"QSENV2-{key}"
        elif line.startswith("QSENV1:"):
            fields = line.split(":")
            if len(fields) >= 4 and fields[3]:
                return f"QSENV1-{fields[3]}"
        elif line:
            return line
        raise SecretError("Invalid pass file format.")

    def ensure_password(self, read_only=False):
        if not read_only:
            self.ensure_dirs()
        line = self.pass_line(read_only=read_only)
        if not line:
            raise MissingPassword("未检测到本地密钥，请运行 q-secret-env unlock。")
        if read_only:
            return
        if not line.startswith(("QSENV1:", "QSENV2:")):
            # Legacy plaintext passwords originally accompanied raw OpenSSL data.
            # Read all supported containers here to allow recovery after upgrades.
            key = password_key(line)
            if self.enc_file.exists():
                entries = self.read_db(line)
                self.write_db(entries, f"QSENV2-{key}")
            atomic_write(self.pass_file, encode(f"QSENV2:{key}\n"))
        self.pass_file.chmod(0o600)

    def list_index(self):
        if not self.enc_file.exists():
            return []
        lines = self.enc_file.read_bytes().split(b"\n")
        if lines[0] != MAGIC_V2:
            raise SecretError("Legacy encrypted db has no name index; use list --values.")
        return [decode(line.split(b"\t")[1]) for line in lines[1:]
                if line.startswith(b"NAME\t") and line.split(b"\t")[1]]

    def read_db(self, phrase):
        if not self.enc_file.exists():
            return {}
        encrypted = self.enc_file.read_bytes()
        header, _, body = encrypted.partition(b"\n")
        try:
            if header == MAGIC_V2:
                payload = next(line.split(b"\t")[1] for line in body.split(b"\n")
                               if line.startswith(b"DATA\t"))
                encrypted = base64.b64decode(payload, validate=True)
            elif header == MAGIC_V1:
                encrypted = base64.b64decode(b"".join(body.split()), validate=True)
        except (StopIteration, IndexError, ValueError, binascii.Error) as error:
            raise SecretError(f"Failed to decode {self.enc_file}.") from error
        plaintext = crypt(encrypted, phrase, decrypt=True)
        entries = {}
        try:
            for line in plaintext.split(b"\n"):
                if not line:
                    continue
                name, value = line.split(b"\t", 1)
                name = decode(name)
                validate_name(name)
                entries[name] = decode(base64.b64decode(value, validate=True))
                if "\0" in entries[name]:
                    raise ValueError("Environment values cannot contain NUL.")
        except (ValueError, binascii.Error) as error:
            raise SecretError("Invalid encrypted db contents.") from error
        return entries

    def write_db(self, entries, phrase):
        plaintext = b"".join(
            encode(name) + b"\t" + base64.b64encode(encode(value)) + b"\n"
            for name, value in entries.items()
        )
        encrypted = crypt(plaintext, phrase)
        index = b"".join(b"NAME\t" + encode(name) + b"\n" for name in entries)
        atomic_write(self.enc_file, MAGIC_V2 + b"\n" + index
                     + b"DATA\t" + base64.b64encode(encrypted) + b"\n")

    def write_env(self, entries):
        exports = "".join(f"export {name}={shlex.quote(value)}\n"
                          for name, value in entries.items())
        atomic_write(self.env_file, encode(exports))

    def read_password(self, prompt, allow_empty=False):
        if not os.isatty(0) or not os.isatty(2):
            raise SecretError("This command requires an interactive terminal.")
        # Use stderr like Bash read -rsp.
        with warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            try:
                password = getpass.getpass(prompt, stream=sys.stderr)
            except getpass.GetPassWarning as error:
                raise SecretError("Cannot disable terminal echo for hidden input.") from error
        if not password and not allow_empty:
            raise SecretError("Password cannot be empty.")
        return password

    def unlock(self):
        self.ensure_dirs()
        key = password_key(self.read_password("Master password: "))
        entries = self.read_db(f"QSENV2-{key}")
        if self.enc_file.exists():
            self.write_env(entries)
        atomic_write(self.pass_file, encode(f"QSENV2:{key}\n"))
        print("Master password saved.", file=sys.stderr)

    def reset_pass(self):
        self.ensure_dirs()
        if not os.isatty(0) or not os.isatty(2):
            raise SecretError("passwd requires an interactive terminal.")
        has_password = bool(self.pass_line())
        if self.enc_file.exists() and not has_password:
            raise SecretError("Cannot set password: encrypted data exists but old master password is missing.")
        if has_password:
            self.ensure_password()
        password = self.read_password("New master password: ")
        if password != self.read_password("Confirm password: "):
            raise SecretError("Password mismatch.")
        key = password_key(password)
        # Encrypt successfully before replacing the only local decryption key.
        if self.enc_file.exists():
            entries = self.read_db(self.phrase())
            self.write_db(entries, f"QSENV2-{key}")
            atomic_write(self.pass_file, encode(f"QSENV2:{key}\n"))
            self.write_env(entries)
        else:
            atomic_write(self.pass_file, encode(f"QSENV2:{key}\n"))
        print("Master password updated.", file=sys.stderr)

    def run(self, command, args, from_stdin=False):
        if command == "unlock":
            self.unlock()
            return 0
        if command == "passwd":
            self.reset_pass()
            return 0
        if command == "list" and not args:
            for name in self.list_index():
                print(name)
            return 0
        if command in ("get", "set", "unset"):
            validate_name(args[0])
        read_only = command in ("get", "list")
        self.ensure_password(read_only=read_only)
        phrase = self.phrase(read_only=read_only)
        entries = self.read_db(phrase)
        if command in ("get", "unset") and args[0] not in entries:
            raise SecretError(f"Not found: {args[0]}")
        if command == "set":
            if from_stdin:
                value = decode(sys.stdin.buffer.read())
            elif args[1] is None:
                value = self.read_password(f"Value for {args[0]}: ", allow_empty=True)
            else:
                value = args[1]
            if "\0" in value:
                raise SecretError("Environment values cannot contain NUL.")
            entries[args[0]] = value
            self.write_db(entries, phrase)
        elif command == "unset":
            del entries[args[0]]
            self.write_db(entries, phrase)
        if command in ("set", "unset", "sync"):
            self.write_env(entries)
        if command == "list":
            for name, value in entries.items():
                print(f"{name}\t{value}")
        elif command == "get":
            print(entries[args[0]])
        elif command == "set":
            print(f"Saved: {args[0]}", file=sys.stderr)
        elif command == "unset":
            print(f"Removed: {args[0]}", file=sys.stderr)
        return 0


def build_parser():
    parser = argparse.ArgumentParser(
        prog="q-secret-env",
        description="Manage encrypted environment variables.",
        epilog="Env names are public; values are encrypted with OpenSSL. "
               "Local key and decrypted exports stay under "
               "$XDG_CONFIG_HOME/q-secret-env (default: ~/.config/q-secret-env).",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list", help="List encrypted env names")
    listing.add_argument("--values", action="store_true",
                         help="Decrypt and print all values")
    getter = commands.add_parser("get", help="Decrypt and print one value")
    getter.add_argument("name", metavar="NAME", type=parse_env_name)
    setter = commands.add_parser("set", help="Add or update an env entry")
    setter.add_argument("name", metavar="NAME", type=parse_env_name)
    value_source = setter.add_mutually_exclusive_group()
    value_source.add_argument("value", metavar="VALUE", nargs="?",
                              help="Value to save; omit for hidden interactive input")
    value_source.add_argument("--stdin", dest="from_stdin", action="store_true",
                              help="Read the exact value from stdin, including trailing newlines")
    removal = commands.add_parser("unset", help="Remove an env entry")
    removal.add_argument("name", metavar="NAME", type=parse_env_name)
    commands.add_parser("unlock", help="Verify master password and save the local key")
    commands.add_parser("passwd", help="Set or rotate master password interactively")
    commands.add_parser("sync", help="Refresh local env.zsh from encrypted data")
    return parser


def main(argv=None):
    parser = build_parser()
    argv = sys.argv[1:] if argv is None else argv
    if not argv:
        parser.print_help()
        return 0
    parsed = parser.parse_args(argv)
    args = []
    if parsed.command in ("get", "set", "unset"):
        args.append(parsed.name)
    if parsed.command == "set":
        if parsed.value is None and not parsed.from_stdin and (
            not os.isatty(0) or not os.isatty(2)
        ):
            parser.error("set requires VALUE or --stdin when no interactive terminal is available")
        args.append(parsed.value)
    if parsed.command == "list" and parsed.values:
        args.append("--values")
    try:
        return SecretEnv().run(parsed.command, args, from_stdin=getattr(parsed, "from_stdin", False))
    except (SecretError, OSError, EOFError) as error:
        print(str(error), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print(file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
