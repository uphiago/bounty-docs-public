#!/usr/bin/env python3
"""Print package/version fields from an APK's binary AndroidManifest.xml.

No Android SDK (aapt/apkanalyzer) required: parses the AXML resource directly.
Usage:
    python3 axml-version.py <app.apk>
    python3 axml-version.py <AndroidManifest.xml>
"""
import struct
import sys
import zipfile


def _read_string_pool(data, off):
    strcount, _stylcount, flags, strstart = struct.unpack_from("<IIII", data, off + 8)
    offsets = struct.unpack_from("<%dI" % strcount, data, off + 28)
    utf8 = bool(flags & (1 << 8))
    base = off + strstart
    out = []
    for o in offsets:
        p = base + o
        if utf8:
            n = data[p]
            p += 1
            if n & 0x80:
                n = ((n & 0x7F) << 8) | data[p]
                p += 1
            n2 = data[p]
            p += 1
            if n2 & 0x80:
                n2 = ((n2 & 0x7F) << 8) | data[p]
                p += 1
            out.append(data[p:p + n2].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", data, p)[0]
            p += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", data, p)[0]
                p += 2
            out.append(data[p:p + n * 2].decode("utf-16-le", "replace"))
    return out


def parse_manifest(data):
    assert struct.unpack_from("<H", data, 0)[0] == 0x0003, "not a binary AndroidManifest"
    off, strings, first = 8, [], True
    while off < len(data):
        ctype = struct.unpack_from("<H", data, off)[0]
        csize = struct.unpack_from("<I", data, off + 4)[0]
        if ctype == 0x0001:
            strings = _read_string_pool(data, off)
        elif ctype == 0x0102 and first:  # first start tag = <manifest>
            name_i = struct.unpack_from("<i", data, off + 20)[0]
            attr_start, attr_size, attr_count = struct.unpack_from("<HHH", data, off + 24)
            if 0 <= name_i < len(strings) and strings[name_i] == "manifest":
                attrs = {}
                for a in range(attr_count):
                    ao = off + 16 + attr_start + a * attr_size
                    _ns, anm, raw = struct.unpack_from("<iii", data, ao)
                    _size, _res0, _dtype = struct.unpack_from("<HBB", data, ao + 12)
                    ddata = struct.unpack_from("<i", data, ao + 16)[0]
                    nm = strings[anm] if 0 <= anm < len(strings) else str(anm)
                    rv = strings[raw] if 0 <= raw < len(strings) else None
                    attrs[nm] = rv if rv is not None else ddata
                return attrs
        off += csize or 4
    return {}


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 1
    path = argv[1]
    if path.lower().endswith(".apk") or zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            data = z.read("AndroidManifest.xml")
    else:
        data = open(path, "rb").read()
    attrs = parse_manifest(data)
    for key in ("package", "versionCode", "versionName", "compileSdkVersion",
                "minSdkVersion", "targetSdkVersion", "requiredSplitTypes"):
        if key in attrs:
            print("%s=%s" % (key, attrs[key]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
