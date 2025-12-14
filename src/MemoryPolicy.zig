const std = @import("std");

pub const MemoryPolicy = struct {
    /// Half-life for confidence decay (7 days default)
    half_life_ms: i64 = 7 * 24 * 60 * 60 * 1000,

    /// Below this confidence, memories deactivate
    deactivate_below: f32 = 0.20,

    /// Small epsilon for comparison stability
    epsilon: f32 = 0.0001,

    pub fn decayConfidence(self: MemoryPolicy, initial: f32, age_ms: i64) f32 {
        if (age_ms <= 0) return clamp01(initial);
        if (self.half_life_ms <= 0) return clamp01(initial);

        const exponent: f64 = @as(f64, @floatFromInt(age_ms)) /
            @as(f64, @floatFromInt(self.half_life_ms));

        const factor: f64 = std.math.pow(f64, 0.5, exponent);
        const decayed: f64 = @as(f64, initial) * factor;

        return clamp01(@as(f32, @floatCast(decayed)));
    }
};

fn clamp01(x: f32) f32 {
    if (x < 0.0) return 0.0;
    if (x > 1.0) return 1.0;
    return x;
}

test "MemoryPolicy decay halves at half-life" {
    const p = MemoryPolicy{ .half_life_ms = 1000 };
    const c0: f32 = 1.0;
    const c1 = p.decayConfidence(c0, 1000);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), c1, 0.0005);
}

test "MemoryPolicy decay is stable at age 0" {
    const p = MemoryPolicy{ .half_life_ms = 1000 };
    const c0: f32 = 0.7;
    const c1 = p.decayConfidence(c0, 0);
    try std.testing.expectApproxEqAbs(c0, c1, 0.00001);
}
