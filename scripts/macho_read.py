"""Small read-only Mach-O arm64 reader for local UI code investigation."""
from pathlib import Path
import struct

class Image:
    def __init__(self, path):
        self.data = Path(path).read_bytes()
        base = 0
        if self.data[:4] == b'\xca\xfe\xba\xbe':
            count = struct.unpack_from('>I', self.data, 4)[0]
            for i in range(count):
                cpu, subtype, offset, size, align = struct.unpack_from('>IIIII', self.data, 8 + i*20)
                if cpu == 0x100000c:
                    base = offset
                    break
            else:
                raise ValueError('No arm64 slice')
        magic, cpu, subtype, kind, count, _, _, _ = struct.unpack_from('<8I', self.data, base)
        assert magic == 0xfeedfacf and cpu == 0x100000c
        self.sections = []
        pos = base + 32
        for _ in range(count):
            cmd, size = struct.unpack_from('<II', self.data, pos)
            if cmd == 0x19:
                nsects = struct.unpack_from('<I', self.data, pos+64)[0]
                for i in range(nsects):
                    p = pos + 72 + i*80
                    sect, seg, addr, length, offset = struct.unpack_from('<16s16sQQI', self.data, p)
                    self.sections.append((sect.rstrip(b'\0').decode(), seg.rstrip(b'\0').decode(), addr, length, base+offset))
            pos += size

    def read(self, address, size):
        for _, _, addr, length, offset in self.sections:
            if addr <= address and address+size <= addr+length:
                return self.data[offset+address-addr:offset+address-addr+size]
        raise ValueError(f'Address outside file sections: {address:#x}')

    def words(self):
        for name, _, addr, length, offset in self.sections:
            if name == '__text':
                for i, (word,) in enumerate(struct.iter_unpack('<I', self.data[offset:offset+length])):
                    yield addr+4*i, word

    def immediates(self, values):
        """Find adjacent 32-bit MOVZ low/MOVK high pairs, not all ARM constants."""
        last = (0, 0)
        for addr, word in self.words():
            prev_addr, prev = last
            if prev & 0xffe00000 == 0x52800000 and word & 0xffe00000 == 0x72a00000 and prev & 31 == word & 31:
                value = ((prev >> 5) & 0xffff) | (((word >> 5) & 0xffff) << 16)
                if value in values:
                    print(hex(prev_addr), 'w'+str(word&31), hex(value), value.to_bytes(4, 'big'))
            last = (addr, word)

    def strings(self, names):
        found = {}
        for section, _, addr, length, offset in self.sections:
            if section not in ('__cstring', '__const'): continue
            data = self.data[offset:offset+length]
            for name in names:
                needle = name.encode() + b'\0'
                start = 0
                while (pos := data.find(needle, start)) >= 0:
                    found[addr+pos] = name
                    start = pos+1
        return found

    def address_refs(self, targets):
        pages = {}
        for addr, word in self.words():
            if word & 0x9f000000 == 0x90000000:  # ADRP
                imm = ((word >> 29) & 3) | (((word >> 5) & 0x7ffff) << 2)
                if imm & (1 << 20): imm -= 1 << 21
                pages[word & 31] = (addr, (addr & ~4095) + (imm << 12))
            elif word & 0xffc00000 == 0x91000000:  # ADD Xd, Xn, #imm12
                reg = (word >> 5) & 31
                if reg in pages:
                    origin, page = pages[reg]
                    target = page + ((word >> 10) & 4095)
                    if addr-origin <= 40 and target in targets:
                        print(hex(origin), hex(addr), hex(target), targets[target])

if __name__ == '__main__':
    import sys
    img = Image('/Applications/Ableton Live 12 Trial.app/Contents/MacOS/Live')
    img.immediates({int.from_bytes(s.encode(), 'big') for s in sys.argv[1:]})
