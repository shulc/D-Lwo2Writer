/// LWO2 (LightWave object) reader — the inverse of `lwo2.writer`.
///
/// Pure D, no external dependencies (compiles under the `core` configuration).
/// Parses an LWO2 IFF container into the same `Lwo2Object` the writer consumes,
/// so a `readLwo2(buildLwo2(obj))` round-trips geometry, the PTCH subpatch flag,
/// and surfaces. UV maps (VMAP/VMAD) are skipped at this stage; the chunk loop
/// passes over them by their (even-padded) size, leaving `vmaps`/`vmads` empty.
///
/// The reader walks the top-level chunk list, validating the `FORM`/`LWO2`
/// wrapper, advancing by each chunk's unpadded size plus the IFF even pad. It
/// honours the LWO2 poly-index contract (the reader half of D-2): on-disk PTAG
/// poly indices are POLS-LOCAL (0-based within the most-recent POLS chunk of a
/// given kind), so the reader records, per POLS chunk it parses, the mapping
/// `(kind, local) -> obj.polygons[] slot` and remaps PTAG entries back to
/// `obj.polygons[]` index space before storing them.
///
/// Tolerant: unknown top-level chunks and curve POLS kinds are skipped by size;
/// malformed or truncated input throws a typed `Lwo2ReadException` rather than
/// corrupting state. Multi-layer is out of scope — geometry/surfaces accumulate
/// into a single `Lwo2Object` (the writer emits one LAYR 0).
///
/// Format reference:
///   https://docs.lightwave3d.com/2025/lightwave-object-format.html
module lwo2.reader;

import lwo2.writer : Lwo2Object, Lwo2Polygon, Lwo2Surface;

/// Thrown on malformed, truncated, or non-LWO2 input.
class Lwo2ReadException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow
    {
        super(msg, file, line);
    }
}

/// Parse an in-memory LWO2 file image into an `Lwo2Object`.
Lwo2Object readLwo2(const(ubyte)[] bytes)
{
    auto cur = Cursor(bytes);

    // --- FORM .. LWO2 wrapper ---------------------------------------------
    if (cur.remaining < 12)
        throw new Lwo2ReadException("file too small for a FORM/LWO2 header");
    if (cur.id4() != "FORM")
        throw new Lwo2ReadException("not an IFF file (missing FORM magic)");
    uint formLen = cur.getU4();
    // The FORM length covers the form type + every chunk; the whole file is
    // formLen + 8 (the "FORM" id + the u4 length field are not counted).
    if (cast(size_t) formLen + 8 != bytes.length)
        throw new Lwo2ReadException("FORM length does not match file size");
    if (cur.id4() != "LWO2")
        throw new Lwo2ReadException("not an LWO2 file (wrong form type)");

    Lwo2Object obj;
    string[] tags;                 // TAGS surface-name table (held until SURF)

    // Reader half of D-2: per-kind POLS-local -> obj.polygons[] slot. Indexed
    // by POLS kind (0 = FACE, 1 = PTCH); each entry is the obj.polygons[] slot
    // a poly was appended to, in on-disk POLS order. `lastPolsKind` records the
    // kind of the most-recent POLS chunk so PTAG (and later VMAD) can bind.
    size_t[][2] localToGlobal;
    int lastPolsKind = -1;         // -1 == no POLS seen yet

    // --- top-level chunk loop ---------------------------------------------
    while (cur.remaining >= 8)
    {
        string id = cur.id4();
        uint size = cur.getU4();
        if (cur.offset + size > bytes.length)
            throw new Lwo2ReadException("chunk '" ~ id ~ "' size overruns file");

        // Carve the chunk body as its own sub-cursor (bounded by `size`); the
        // outer cursor advances past the body + even pad afterwards.
        auto chunkEnd = cur.offset + size;
        auto sub = Cursor(bytes[cur.offset .. chunkEnd]);

        switch (id)
        {
        case "LAYR":
            // COMPACT LWO2 LAYR: u2 number, u2 flags, f4x3 pivot, S0 name.
            // (No extended tail — this is the LWO2 form, not the LXO one.)
            if (sub.remaining >= 2 + 2 + 12)
            {
                sub.getU2();           // layer number (single layer 0; ignored)
                sub.getU2();           // flags (ignored)
                sub.getF4(); sub.getF4(); sub.getF4(); // pivot (ignored)
                obj.layerName = sub.getS0();
            }
            break;

        case "TAGS":
            // Null-terminated, even-padded surface names, packed until the
            // chunk is consumed.
            while (sub.remaining > 0)
                tags ~= sub.getS0();
            break;

        case "PNTS":
            // f4 x/y/z per point. size must be a multiple of 12.
            if (size % 12 != 0)
                throw new Lwo2ReadException("PNTS size is not a multiple of 12");
            {
                size_t n = size / 12;
                obj.points.length = n;
                foreach (i; 0 .. n)
                    obj.points[i] = [sub.getF4(), sub.getF4(), sub.getF4()];
            }
            break;

        case "BBOX":
            // Ignored: the writer recomputes the bounding box from PNTS, so a
            // round-trip reproduces it identically. Skip the body.
            break;

        case "POLS":
            parsePols(sub, obj, localToGlobal, lastPolsKind);
            break;

        case "PTAG":
            parsePtag(sub, obj, localToGlobal, lastPolsKind);
            break;

        case "SURF":
            obj.surfaces ~= parseSurf(sub);
            break;

        // VMAP/VMAD: parsed in Stage 4. Skipped here by size (the body sub is
        // discarded; the outer cursor advances past it below).
        case "VMAP":
        case "VMAD":
        default:
            // Unknown chunks and curve POLS kinds (handled inside parsePols)
            // fall through and are skipped by size.
            break;
        }

        // Advance the outer cursor past the body and the IFF even pad. The
        // size field is the UNPADDED length; a pad byte at an odd body length
        // is not counted by `size` but is present in the stream.
        cur.skip(size);
        if (size & 1)
            cur.skip(1);
    }

    return obj;
}

/// Read a file from `path` and parse it as LWO2.
Lwo2Object readLwo2File(string path)
{
    import std.file : read;
    return readLwo2(cast(const(ubyte)[]) read(path));
}

// ---------------------------------------------------------------------------
// Chunk parsers
// ---------------------------------------------------------------------------

/// Parse a single POLS chunk: ID4 kind, then per poly `[u2 count][VX*count]`.
/// FACE -> subpatch=false, PTCH -> subpatch=true; curve kinds are skipped (the
/// whole chunk is consumed by reading to its end, but curve polys are NOT
/// appended). Records the reader-half D-2 map for the supported kinds.
private void parsePols(ref Cursor sub, ref Lwo2Object obj,
                       ref size_t[][2] localToGlobal, ref int lastPolsKind)
{
    if (sub.remaining < 4)
        throw new Lwo2ReadException("POLS chunk too small for a kind id");
    string kind = sub.id4();

    int kindIdx;
    if (kind == "FACE")      kindIdx = 0;
    else if (kind == "PTCH") kindIdx = 1;
    else
    {
        // Curve POLS kinds (LINE/HCRV/BCRV/BSPL/TEXT/...) are out of scope:
        // consume and skip (do not append, do not bind PTAG). lastPolsKind is
        // left untouched so a following PTAG binds to the previous supported
        // POLS — but a real file would not interleave that way. We simply do
        // not record this kind.
        return;
    }

    lastPolsKind = kindIdx;
    bool subpatch = (kindIdx == 1);

    while (sub.remaining > 0)
    {
        // u2 vertex count; high 6 bits are flags -> mask to 0x03FF.
        ushort raw = sub.getU2();
        uint count = raw & 0x03FF;
        if (count == 0)
            throw new Lwo2ReadException("POLS polygon has zero vertices");
        uint[] idx;
        idx.length = count;
        foreach (i; 0 .. count)
            idx[i] = sub.getVX();

        obj.polygons ~= Lwo2Polygon(idx, 0, subpatch);
        // Record (kind, local) -> obj.polygons[] slot in on-disk POLS order.
        localToGlobal[kindIdx] ~= obj.polygons.length - 1;
    }
}

/// Parse a PTAG SURF chunk: ID4 type, then per-entry `[VX poly][u2 tag]`. The
/// on-disk poly index is POLS-LOCAL to the most-recent POLS chunk; map it back
/// to an obj.polygons[] slot via `localToGlobal[lastPolsKind]`.
private void parsePtag(ref Cursor sub, ref Lwo2Object obj,
                       ref size_t[][2] localToGlobal, ref int lastPolsKind)
{
    if (sub.remaining < 4)
        throw new Lwo2ReadException("PTAG chunk too small for a type id");
    string ptagType = sub.id4();
    if (ptagType != "SURF")
        return;                    // only SURF poly->surface tags are consumed
    if (lastPolsKind < 0)
        throw new Lwo2ReadException("PTAG SURF with no preceding POLS chunk");

    auto map = localToGlobal[lastPolsKind];
    while (sub.remaining > 0)
    {
        uint local = sub.getVX();
        ushort tag = sub.getU2();
        if (local >= map.length)
            throw new Lwo2ReadException("PTAG poly index out of range for its POLS");
        obj.polygons[map[local]].surface = tag;
    }
}

/// Parse a SURF chunk into an `Lwo2Surface`, mirroring what `buildLwo2` writes:
/// S0 name, S0 parent (ignored), then COLR/DIFF/SPEC/GLOS/TRAN sub-chunks.
/// Unknown sub-chunks are skipped by their (even-padded) size. TRAN is stored
/// as `opacity = 1 - tran`.
private Lwo2Surface parseSurf(ref Cursor sub)
{
    Lwo2Surface s;
    s.name = sub.getS0();
    sub.getS0();                   // parent surface name (none; ignored)

    while (sub.remaining >= 6)
    {
        string scid = sub.id4();
        ushort sclen = sub.getU2();
        if (sub.offset + sclen > sub.length)
            throw new Lwo2ReadException("SURF sub-chunk '" ~ scid ~ "' overruns");
        auto scEnd = sub.offset + sclen;
        auto sc = Cursor(sub.slice[sub.offset .. scEnd]);

        switch (scid)
        {
        case "COLR":
            // COL12 base color (f4 x3) + envelope VX (ignored).
            if (sc.remaining >= 12)
                s.baseColor = [sc.getF4(), sc.getF4(), sc.getF4()];
            break;
        case "DIFF": s.diffuse    = readF4SubChunk(sc); break;
        case "SPEC": s.specular   = readF4SubChunk(sc); break;
        case "GLOS": s.glossiness = readF4SubChunk(sc); break;
        case "TRAN": s.opacity    = 1.0f - readF4SubChunk(sc); break;
        default: break;            // skip unknown sub-chunk by size
        }

        sub.skip(sclen);
        if (sclen & 1)
            sub.skip(1);
    }
    return s;
}

/// A SURF F4 sub-chunk body: a single F4 value followed by an envelope-ref VX
/// (which the writer always emits as 0; ignored here).
private float readF4SubChunk(ref Cursor sc)
{
    if (sc.remaining < 4)
        throw new Lwo2ReadException("F4 SURF sub-chunk too small");
    return sc.getF4();
}

// ---------------------------------------------------------------------------
// Byte cursor + big-endian / IFF primitive reads (mirror writer.d's put*)
// ---------------------------------------------------------------------------

private struct Cursor
{
    const(ubyte)[] slice;
    size_t offset = 0;

    this(const(ubyte)[] s) { slice = s; }

    size_t length()    const { return slice.length; }
    size_t remaining() const { return slice.length - offset; }

    void need(size_t n, string what)
    {
        if (offset + n > slice.length)
            throw new Lwo2ReadException("truncated input reading " ~ what);
    }

    void skip(size_t n)
    {
        need(n, "skip");
        offset += n;
    }

    /// 4-byte ASCII chunk/type id.
    string id4()
    {
        need(4, "ID4");
        auto s = cast(string)(slice[offset .. offset + 4].idup);
        offset += 4;
        return s;
    }

    ushort getU2()
    {
        need(2, "U2");
        ushort v = cast(ushort)((slice[offset] << 8) | slice[offset + 1]);
        offset += 2;
        return v;
    }

    uint getU4()
    {
        need(4, "U4");
        uint v = (cast(uint) slice[offset]     << 24)
               | (cast(uint) slice[offset + 1] << 16)
               | (cast(uint) slice[offset + 2] << 8)
               |  cast(uint) slice[offset + 3];
        offset += 4;
        return v;
    }

    float getF4() @trusted
    {
        uint bits = getU4();
        return *cast(float*) &bits;
    }

    /// Variable-length index (VX): a u16 if < 0xFF00; otherwise a 4-byte form
    /// with the high byte 0xFF, value = ((a << 16) | b) & 0x00FF_FFFF.
    uint getVX()
    {
        need(2, "VX");
        ushort a = cast(ushort)((slice[offset] << 8) | slice[offset + 1]);
        if (a < 0xFF00)
        {
            offset += 2;
            return a;
        }
        // 4-byte form: re-read both halves as two u16.
        need(4, "VX (4-byte)");
        ushort b = cast(ushort)((slice[offset + 2] << 8) | slice[offset + 3]);
        offset += 4;
        return ((cast(uint) a << 16) | cast(uint) b) & 0x00FF_FFFFu;
    }

    /// Null-terminated string, padded to an even byte length (S0). The pad byte
    /// (present only when the string-plus-terminator length is odd) is consumed.
    string getS0()
    {
        size_t start = offset;
        while (offset < slice.length && slice[offset] != 0)
            offset++;
        if (offset >= slice.length)
            throw new Lwo2ReadException("unterminated S0 string");
        auto s = cast(string)(slice[start .. offset].idup);
        offset++;                  // consume the NUL terminator
        // Even-pad: total bytes consumed (chars + NUL) must be even.
        size_t consumed = offset - start;
        if (consumed & 1)
        {
            need(1, "S0 pad");
            offset++;
        }
        return s;
    }
}
