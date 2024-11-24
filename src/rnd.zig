const std = @import("std");

pub const Rnd = struct
{
    const OFFSET: u64 = 0x7f7110ba7879ea6a;
    seed: u64,

    pub fn init(seed: u64) Rnd
    {
        return Rnd
        {
            .seed = OFFSET *% seed,
        };
    }

    pub fn init_randomized() Rnd
    {
        return Rnd
        {
            .seed = OFFSET *% generate_timeseed(),
        };
    }

    fn generate_timeseed() u64
    {
        const t: i64 = std.time.microTimestamp();
        const u: u64 = @intCast(t);
        return u;
    }

    pub fn reset_seed(self: *Rnd, seed: u64) void
    {
        self.seed = OFFSET *% seed;
    }

    pub fn next_u64(self: *Rnd) u64
    {
        self.seed = self.seed +% 0x9e3779b97f4a7c15;
        var z: u64 = self.seed;
        z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
        z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
        z = (z ^ (z >> 31));
        return z;
    }

    pub fn next_u32(self: *Rnd) u32
    {
        const n: u64 = self.next_u64();
        const a: u32 = @truncate(n);
        const b: u32 = @truncate(n >> 32);
        return a ^ b;
    }

    pub fn next_u64_range(self: *Rnd, min: u64, max: u64) u64
    {
        if (max > min)
        {
            const range: u64 = max - min;
            const n = self.next_u64() % range + min;
            return n;
        }
        else
        {
            return max;
        }
    }

};


// https://research.kudelskisecurity.com/2020/07/28/the-definitive-guide-to-modulo-bias-and-how-to-avoid-it/

// We suggest to use SplitMix64 to initialize the state of our generators starting from a 64-bit seed,
// as research has shown that initialization must be performed with a generator radically different in nature from the one initialized to avoid correlation on similar seeds.

// #include <stdint.h>

//  This is a fixed-increment version of Java 8's SplittableRandom generator
//    See http://dx.doi.org/10.1145/2714064.2660195 and
//    http://docs.oracle.com/javase/8/docs/api/java/util/SplittableRandom.html

//    It is a very fast generator passing BigCrush, and it can be useful if
//    for some reason you absolutely want 64 bits of state. */

// static uint64_t x; /* The state can be seeded with any value. */

// uint64_t next() {
// 	uint64_t z = (x += 0x9e3779b97f4a7c15);
// 	z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
// 	z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
// 	return z ^ (z >> 31);
// }

// Magic Constants: The constants 0x9e3779b97f4a7c15, 0xbf58476d1ce4e5b9, 0x94d049bb133111eb are often called "magic" or "mixing" constants in hash functions.
// They are chosen for their properties to mix the bits of the input well. Ensure these are correctly translated from the C code and their usage is appropriate.



