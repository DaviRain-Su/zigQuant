// Decimal - High-precision decimal number type for financial calculations
//
// Provides a fixed-point decimal type to avoid floating-point precision issues.
// Uses i128 integer internally with a fixed scale of 18 decimal places.
//
// Design principles:
// - Precision: 18 decimal places (sufficient for financial calculations)
// - Safety: Overflow detection and error handling
// - Simplicity: Fixed scale (no dynamic precision)
// - Performance: Integer-based arithmetic
//
// Example:
//   const a = try Decimal.fromString("0.1");
//   const b = try Decimal.fromString("0.2");
//   const c = a.add(b);  // Exactly 0.3, no floating-point error

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Decimal Type Definition
// ============================================================================

pub const Decimal = struct {
    /// Internal value stored as i128 integer
    /// Actual value = value / MULTIPLIER
    value: i128,

    /// Scale (number of decimal places, fixed at 18)
    scale: u8,

    // Constants
    pub const SCALE: u8 = 18;
    pub const MULTIPLIER: i128 = 1_000_000_000_000_000_000; // 10^18

    pub const ZERO: Decimal = .{ .value = 0, .scale = SCALE };
    pub const ONE: Decimal = .{ .value = MULTIPLIER, .scale = SCALE };

    // ========================================================================
    // Constructors
    // ========================================================================

    /// Create Decimal from integer
    pub fn fromInt(i: i64) Decimal {
        return .{
            .value = @as(i128, i) * MULTIPLIER,
            .scale = SCALE,
        };
    }

    /// Create Decimal from floating-point number
    /// Warning: May lose precision due to f64 representation
    pub fn fromFloat(f: f64) Decimal {
        const scaled = f * @as(f64, @floatFromInt(MULTIPLIER));
        return .{
            .value = @as(i128, @intFromFloat(scaled)),
            .scale = SCALE,
        };
    }

    /// Create Decimal from string representation
    /// Supports formats: "123", "123.456", "-123.456"
    pub fn fromString(s: []const u8) !Decimal {
        if (s.len == 0) return error.EmptyString;

        var pos: usize = 0;
        var negative = false;

        // Handle sign
        if (s[0] == '-') {
            negative = true;
            pos = 1;
        } else if (s[0] == '+') {
            pos = 1;
        }

        if (pos >= s.len) return error.InvalidFormat;

        // Find decimal point
        var decimal_pos: ?usize = null;
        for (s[pos..], pos..) |c, i| {
            if (c == '.') {
                if (decimal_pos != null) return error.MultipleDecimalPoints;
                decimal_pos = i;
            } else if (c < '0' or c > '9') {
                return error.InvalidCharacter;
            }
        }

        // Parse integer part
        var result: i128 = 0;
        const int_end = decimal_pos orelse s.len;

        for (s[pos..int_end]) |c| {
            const digit = c - '0';
            result = result * 10 + digit;
        }

        // Scale up to full precision
        result *= MULTIPLIER;

        // Parse decimal part if present
        if (decimal_pos) |dot_pos| {
            const frac_start = dot_pos + 1;
            if (frac_start >= s.len) return error.InvalidFormat;

            var frac_value: i128 = 0;
            var frac_digits: u8 = 0;

            for (s[frac_start..]) |c| {
                if (frac_digits >= SCALE) break; // Truncate extra precision
                const digit = c - '0';
                frac_value = frac_value * 10 + digit;
                frac_digits += 1;
            }

            // Scale fractional part to full precision
            var scale_factor: i128 = 1;
            var i: u8 = frac_digits;
            while (i < SCALE) : (i += 1) {
                scale_factor *= 10;
            }
            result += frac_value * scale_factor;
        }

        if (negative) {
            result = -result;
        }

        return .{
            .value = result,
            .scale = SCALE,
        };
    }

    // ========================================================================
    // Conversion Functions
    // ========================================================================

    /// Convert to f64 (may lose precision)
    pub fn toFloat(self: Decimal) f64 {
        const f_value = @as(f64, @floatFromInt(self.value));
        const f_multiplier = @as(f64, @floatFromInt(MULTIPLIER));
        return f_value / f_multiplier;
    }

    /// Convert to string
    /// Allocates memory that must be freed by the caller
    pub fn toString(self: Decimal, allocator: Allocator) ![]const u8 {
        var buf = try std.ArrayList(u8).initCapacity(allocator, 64);
        errdefer buf.deinit(allocator);

        const abs_value = if (self.value < 0) -self.value else self.value;

        // Handle sign
        if (self.value < 0) {
            try buf.appendSlice(allocator, "-");
        }

        // Integer part
        const int_part = @divTrunc(abs_value, MULTIPLIER);
        const int_str = try std.fmt.allocPrint(allocator, "{d}", .{int_part});
        defer allocator.free(int_str);
        try buf.appendSlice(allocator, int_str);

        // Fractional part
        const frac_part = @rem(abs_value, MULTIPLIER);
        if (frac_part != 0) {
            try buf.appendSlice(allocator, ".");

            // Convert fractional part to string with exactly 18 digits
            // We need to pad with leading zeros
            var frac_digits: [18]u8 = undefined;
            var temp = frac_part;
            var i: usize = 18;
            while (i > 0) {
                i -= 1;
                frac_digits[i] = @as(u8, @intCast(@rem(temp, 10))) + '0';
                temp = @divTrunc(temp, 10);
            }

            // Trim trailing zeros
            var end: usize = 18;
            while (end > 0 and frac_digits[end - 1] == '0') {
                end -= 1;
            }

            try buf.appendSlice(allocator, frac_digits[0..end]);
        }

        return buf.toOwnedSlice(allocator);
    }

    // ========================================================================
    // Arithmetic Operations
    // ========================================================================

    /// Add two decimals
    pub fn add(self: Decimal, other: Decimal) Decimal {
        std.debug.assert(self.scale == other.scale);
        return .{
            .value = self.value + other.value,
            .scale = self.scale,
        };
    }

    /// Subtract two decimals
    pub fn sub(self: Decimal, other: Decimal) Decimal {
        std.debug.assert(self.scale == other.scale);
        return .{
            .value = self.value - other.value,
            .scale = self.scale,
        };
    }

    /// Multiply two decimals
    /// Uses i256 intermediate to prevent overflow
    pub fn mul(self: Decimal, other: Decimal) Decimal {
        const a = @as(i256, self.value);
        const b = @as(i256, other.value);
        const product = a * b;
        const scaled = @divTrunc(product, MULTIPLIER);

        return .{
            .value = @as(i128, @intCast(scaled)),
            .scale = self.scale,
        };
    }

    /// Divide two decimals
    /// Returns error if dividing by zero
    pub fn div(self: Decimal, other: Decimal) !Decimal {
        if (other.value == 0) {
            return error.DivisionByZero;
        }

        const a = @as(i256, self.value) * MULTIPLIER;
        const b = @as(i256, other.value);
        const quotient = @divTrunc(a, b);

        return .{
            .value = @as(i128, @intCast(quotient)),
            .scale = self.scale,
        };
    }

    // ========================================================================
    // Comparison Operations
    // ========================================================================

    /// Compare two decimals
    /// Returns .lt, .eq, or .gt
    pub fn cmp(self: Decimal, other: Decimal) std.math.Order {
        return std.math.order(self.value, other.value);
    }

    /// Check equality
    pub fn eql(self: Decimal, other: Decimal) bool {
        return self.value == other.value;
    }

    // ========================================================================
    // Utility Functions
    // ========================================================================

    /// Check if zero
    pub fn isZero(self: Decimal) bool {
        return self.value == 0;
    }

    /// Check if positive
    pub fn isPositive(self: Decimal) bool {
        return self.value > 0;
    }

    /// Check if negative
    pub fn isNegative(self: Decimal) bool {
        return self.value < 0;
    }

    /// Get absolute value
    pub fn abs(self: Decimal) Decimal {
        return .{
            .value = if (self.value < 0) -self.value else self.value,
            .scale = self.scale,
        };
    }

    /// Negate the value
    pub fn negate(self: Decimal) Decimal {
        return .{
            .value = -self.value,
            .scale = self.scale,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Decimal: constants" {
    try testing.expect(Decimal.ZERO.isZero());
    try testing.expect(Decimal.ONE.eql(try Decimal.fromString("1")));
    try testing.expectEqual(@as(u8, 18), Decimal.SCALE);
}

test "Decimal: fromInt" {
    const d = Decimal.fromInt(123);
    try testing.expectEqual(@as(i128, 123 * Decimal.MULTIPLIER), d.value);
    try testing.expectEqual(@as(f64, 123.0), d.toFloat());
}

test "Decimal: fromFloat" {
    const d = Decimal.fromFloat(123.456);
    const f = d.toFloat();
    try testing.expectApproxEqAbs(@as(f64, 123.456), f, 0.000001);
}

test "Decimal: fromString - integers" {
    const d1 = try Decimal.fromString("123");
    try testing.expectEqual(@as(f64, 123.0), d1.toFloat());

    const d2 = try Decimal.fromString("-456");
    try testing.expectEqual(@as(f64, -456.0), d2.toFloat());

    const d3 = try Decimal.fromString("+789");
    try testing.expectEqual(@as(f64, 789.0), d3.toFloat());
}

test "Decimal: fromString - decimals" {
    const d1 = try Decimal.fromString("123.456");
    try testing.expectApproxEqAbs(@as(f64, 123.456), d1.toFloat(), 0.000001);

    const d2 = try Decimal.fromString("-0.123");
    try testing.expectApproxEqAbs(@as(f64, -0.123), d2.toFloat(), 0.000001);

    const d3 = try Decimal.fromString("0.1");
    try testing.expectApproxEqAbs(@as(f64, 0.1), d3.toFloat(), 0.000001);
}

test "Decimal: fromString - errors" {
    try testing.expectError(error.EmptyString, Decimal.fromString(""));
    try testing.expectError(error.InvalidFormat, Decimal.fromString("-"));
    try testing.expectError(error.InvalidFormat, Decimal.fromString("123."));
    try testing.expectError(error.InvalidCharacter, Decimal.fromString("12a3"));
    try testing.expectError(error.MultipleDecimalPoints, Decimal.fromString("1.2.3"));
}

test "Decimal: toString" {
    const d1 = try Decimal.fromString("123.456");
    const s1 = try d1.toString(testing.allocator);
    defer testing.allocator.free(s1);
    try testing.expectEqualStrings("123.456", s1);

    const d2 = try Decimal.fromString("-0.5");
    const s2 = try d2.toString(testing.allocator);
    defer testing.allocator.free(s2);
    try testing.expectEqualStrings("-0.5", s2);

    const d3 = Decimal.ZERO;
    const s3 = try d3.toString(testing.allocator);
    defer testing.allocator.free(s3);
    try testing.expectEqualStrings("0", s3);
}

test "Decimal: add" {
    const a = try Decimal.fromString("100.5");
    const b = try Decimal.fromString("50.25");
    const sum = a.add(b);

    const expected = try Decimal.fromString("150.75");
    try testing.expect(sum.eql(expected));
}

test "Decimal: sub" {
    const a = try Decimal.fromString("100.5");
    const b = try Decimal.fromString("50.25");
    const diff = a.sub(b);

    const expected = try Decimal.fromString("50.25");
    try testing.expect(diff.eql(expected));
}

test "Decimal: mul" {
    const a = try Decimal.fromString("10.5");
    const b = try Decimal.fromString("2");
    const product = a.mul(b);

    const expected = try Decimal.fromString("21");
    try testing.expect(product.eql(expected));
}

test "Decimal: div" {
    const a = try Decimal.fromString("10");
    const b = try Decimal.fromString("2");
    const quotient = try a.div(b);

    const expected = try Decimal.fromString("5");
    try testing.expect(quotient.eql(expected));
}

test "Decimal: div by zero" {
    const a = try Decimal.fromString("10");
    try testing.expectError(error.DivisionByZero, a.div(Decimal.ZERO));
}

test "Decimal: precision - floating point trap" {
    // The classic 0.1 + 0.2 problem
    const a = try Decimal.fromString("0.1");
    const b = try Decimal.fromString("0.2");
    const c = a.add(b);

    const expected = try Decimal.fromString("0.3");
    try testing.expect(c.eql(expected));

    // Verify the string representation is exact
    const s = try c.toString(testing.allocator);
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("0.3", s);
}

test "Decimal: comparison" {
    const a = try Decimal.fromString("100");
    const b = try Decimal.fromString("50");
    const c = try Decimal.fromString("100");

    try testing.expectEqual(std.math.Order.gt, a.cmp(b));
    try testing.expectEqual(std.math.Order.lt, b.cmp(a));
    try testing.expectEqual(std.math.Order.eq, a.cmp(c));
    try testing.expect(a.eql(c));
    try testing.expect(!a.eql(b));
}

test "Decimal: utility functions" {
    const zero = Decimal.ZERO;
    try testing.expect(zero.isZero());
    try testing.expect(!zero.isPositive());
    try testing.expect(!zero.isNegative());

    const pos = try Decimal.fromString("123.456");
    try testing.expect(pos.isPositive());
    try testing.expect(!pos.isNegative());

    const neg = try Decimal.fromString("-123.456");
    try testing.expect(neg.isNegative());
    try testing.expect(!neg.isPositive());

    const abs_neg = neg.abs();
    try testing.expect(abs_neg.eql(pos));

    const negated = pos.negate();
    try testing.expect(negated.eql(neg));
}

test "Decimal: round trip string conversion" {
    const original = "123.456";
    const d = try Decimal.fromString(original);
    const s = try d.toString(testing.allocator);
    defer testing.allocator.free(s);
    try testing.expectEqualStrings(original, s);
}
