#!/usr/bin/env python3
"""Build the Surface Laptop Ultra RT1320 amp firmware for Linux from your own Windows install.

The Realtek driver (RtkSdcaXu.sys) keeps the amp DSP firmware and tuning in RTKDAT_10EC.dat, an
obfuscated, password-protected ZIP. This script finds the de-obfuscation key and the password
inside your copy of RtkSdcaXu.sys, unpacks the Surface set, and writes the files the Linux rt1320
driver loads. Nothing from Realtek or Microsoft is stored in this repository.

usage: extract.py [WINDOWS_DIR] OUT_DIR
"""
import glob, io, os, struct, subprocess, sys, zipfile, zlib

def find_windows():
    out = subprocess.run(['findmnt', '-rn', '-t', 'ntfs,ntfs3,fuseblk', '-o', 'TARGET'],
                         capture_output=True, text=True).stdout.split()
    for m in out:
        if os.path.isdir(os.path.join(m, 'Windows')):
            return os.path.join(m, 'Windows')
    sys.exit('mount the Windows partition (read-only is fine) or pass its Windows directory')

def driver_dir(win):
    pat = os.path.join(win, 'System32/DriverStore/FileRepository/rtksdcaxu_arm_srf.inf_arm64_*')
    dirs = [d for d in glob.glob(pat)
            if os.path.isfile(f'{d}/RtkSdcaXu.sys') and os.path.isfile(f'{d}/RTKDAT_10EC.dat')]
    if not dirs:
        sys.exit(f'no Realtek SDCA driver package under {pat}')
    return max(dirs, key=lambda d: os.path.getmtime(f'{d}/RtkSdcaXu.sys'))

def unchain(buf, key):
    """Undo the obfuscation: one pass per key byte, last byte first, each output byte
    XORed with the previous input byte (the key byte seeds each pass)."""
    b = bytearray(buf)
    for seed in reversed(key):
        prev = seed
        for i, c in enumerate(b):
            b[i] = c ^ prev
            prev = c
    return bytes(b)

def find_key(sys_bytes, dat):
    head = dat[:4]
    for off in range(0, len(sys_bytes) - 12, 4):
        k = sys_bytes[off:off + 12]
        if unchain(head, k) == b'PK\x03\x04':
            return k
    sys.exit('de-obfuscation key not found in RtkSdcaXu.sys (unsupported driver version?)')

def find_password(sys_bytes, zf):
    """The password is built on the stack from literal-pool pieces, each byte XORed with
    (-i-1): a 24-byte run, a 4-byte run after a 4-byte gap, then one immediate byte.
    Rebuild candidates from that layout and keep the one the archive accepts."""
    test = next(i for i in zf.infolist() if i.flag_bits & 1 and i.file_size)
    dec = lambda off, base, n: bytes(sys_bytes[off + j] ^ ((-(base + j) - 1) & 0xff) for j in range(n))
    ok = lambda b: all(0x20 < c < 0x7f for c in b)
    def accepts(pwd):
        try:
            zf.read(test, pwd=pwd)
            return True
        except (RuntimeError, zipfile.BadZipFile, zlib.error):
            return False
    for off in range(0, len(sys_bytes) - 40, 4):
        head = dec(off, 0, 24)
        if not ok(head):
            continue
        tail = dec(off + 28, 24, 4)
        if not ok(tail):
            continue
        for c in range(0x21, 0x7f):
            if accepts(head + tail + bytes([c])):
                return head + tail + bytes([c])
    sys.exit('archive password not found in RtkSdcaXu.sys (unsupported driver version?)')

def dmi(k):
    return open(f'/sys/class/dmi/id/{k}').read().strip().split(' ')[0]

def main():
    args = sys.argv[1:]
    if len(args) not in (1, 2):
        sys.exit(__doc__)
    win, out = (args if len(args) == 2 else [find_windows(), args[0]])
    d = driver_dir(win)
    sysb = open(f'{d}/RtkSdcaXu.sys', 'rb').read()
    dat = open(f'{d}/RTKDAT_10EC.dat', 'rb').read()
    print(f'driver: {d}')
    zf = zipfile.ZipFile(io.BytesIO(unchain(dat, find_key(sysb, dat))))
    pwd = find_password(sysb, zf)
    # RtkSdcaXu picks this set for SUBSYS 0x308E10EC (Surface Laptop Ultra): FWFiles_20 for the
    # amp with SoundWire unique ID 0, FWFiles_22 for unique ID 2.
    rd = lambda n: zf.read(f'Nocturne_A/{n}', pwd=pwd)
    os.makedirs(out, exist_ok=True)
    base = f"{dmi('sys_vendor')}_{dmi('product_name')}_{dmi('product_sku')}"

    images = [(0x3fc000c0, 'FwCode_1320_Legato_3fc000c0.bin'),
              (0x3fc29d80, 'FwCode_1320_Legato_3fc29d80.bin'),
              (0x3fe00000, 'FwCode_1320_Legato_3fe00000.bin'),
              (0x3fe02000, 'FwCode_1320_Legato_3fe02000.bin'),
              (0x3fc2ab80, 'Afx0_1320_LegatoCD_Data.bin'),
              (0x3fc2b780, 'Afx1_1320_LegatoCD_Data.bin')]
    blobs = []
    for addr, name in images:
        data = rd(name)
        if addr == 0x3fc29d80:
            # rt1320 checks byte 9 of this image to tell RT1320 from RT1321 firmware; add the
            # 64-byte "AFX" header it understands (and strips before writing).
            hdr = bytearray(64); hdr[0:4] = b'AFX\0'; hdr[9] = ord('0')
            data = bytes(hdr) + data
        blobs.append((addr, data))
    fw = struct.pack('<Ihh', 0x0a1c5679, len(blobs), 0)
    fw += b''.join(struct.pack('<II', a, len(x)) for a, x in blobs) + b''.join(x for _, x in blobs)
    files = {f'rt1320_{base}.dat': fw}
    for uid, tag in ((0, '20'), (2, '22')):
        files[f'rt1320_RAE_{base}_{uid}.dat'] = rd(f'EQ_{tag}_RAE_XU.bin') + rd(f'EQ_{tag}_UI_XU.bin')
    for name, data in files.items():
        with open(os.path.join(out, name), 'wb') as f:
            f.write(data)
        print(f'{name} ({len(data)} bytes)')

if __name__ == '__main__':
    main()
