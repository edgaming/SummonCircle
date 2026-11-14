-- Wire format: encode/decode and splitting into frames.
Boot()
local P = ns.Protocol

-- Round trip
local data = P.Encode({ t = "HELLO", shards = 9 })
local msg = P.Decode(data)
eq("roundtrip: type", msg and msg.t, "HELLO")
eq("roundtrip: field", msg and msg.shards, 9)
eq("roundtrip: version stamped", msg and msg.v, P.VERSION)
eq("decode: garbage is nil", P.Decode("not a message"), nil)
eq("decode: table without a type is nil", P.Decode(C_EncodingUtil.SerializeCBOR({ shards = 1 })), nil)
eq("decode: non-table is nil", P.Decode(C_EncodingUtil.SerializeCBOR("hi")), nil)

-- Frames
local long = ("x"):rep(P.CHUNK * 2 + 10)
local frames = P.Frames(long, 7)
eq("frames: count", #frames, 3)
eq("frames: header", frames[1]:sub(1, 6), "7:1:3:")
local fits = true
for _, fr in ipairs(frames) do if #fr > 255 then fits = false end end
check("frames: every frame fits in one addon message", fits)
eq("frames: empty data is one frame", #P.Frames("", 1), 1)

-- Reassembly
local A = P.NewAssembler(30)
eq("assemble: partial", A:Feed("Bram Lock", frames[1], 0), nil)
eq("assemble: out of order", A:Feed("Bram Lock", frames[3], 0), nil)
eq("assemble: duplicate ignored", A:Feed("Bram Lock", frames[1], 0), nil)
eq("assemble: complete", A:Feed("Bram Lock", frames[2], 0), long)

local B = P.NewAssembler(30)
B:Feed("Ash Lock", frames[1], 0)
eq("assemble: senders kept apart", B:Feed("Bram Lock", frames[2], 0), nil)
eq("assemble: single frame", B:Feed("Cole Lock", "3:1:1:hello", 0), "hello")
eq("assemble: malformed frame", B:Feed("Cole Lock", "nonsense", 0), nil)
eq("assemble: bad index", B:Feed("Cole Lock", "4:5:2:x", 0), nil)

local C = P.NewAssembler(30)
C:Feed("Ash Lock", frames[1], 0)
C:Feed("Ash Lock", frames[2], 0)
C:Prune(31)
eq("prune: stale half-message dropped", C:Feed("Ash Lock", frames[3], 31), nil)
