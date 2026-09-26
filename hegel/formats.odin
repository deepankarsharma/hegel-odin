package hegel

import "core:encoding/uuid"
import "core:net"
import "core:time/datetime"

import lh "libhegel"

/*
Calendar dates in `[min_value, max_value]`, defaulting to years 1 through
9999. Shrinks towards 2000-01-01.
*/
dates :: proc(min_value: Maybe(datetime.Date) = nil, max_value: Maybe(datetime.Date) = nil) -> Generator(datetime.Date) {
	State :: struct {
		lo, hi: lh.Date,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> datetime.Date {
		s := (^State)(data)
		out: lh.Date
		check(tc, lh.generate_date(tc._ctx, tc._handle, s.lo, s.hi, &out))
		return from_engine_date(out)
	}
	state := State{
		to_engine_date(min_value.? or_else {1, 1, 1}),
		to_engine_date(max_value.? or_else {9999, 12, 31}),
	}
	return {generate, new_clone(state), label_of("hegel_odin.dates")}
}

// Times of day in `[min_value, max_value]`, shrinking towards midnight.
times :: proc(min_value: Maybe(datetime.Time) = nil, max_value: Maybe(datetime.Time) = nil) -> Generator(datetime.Time) {
	State :: struct {
		lo, hi: lh.Time,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> datetime.Time {
		s := (^State)(data)
		out: lh.Time
		check(tc, lh.generate_time(tc._ctx, tc._handle, s.lo, s.hi, &out))
		return from_engine_time(out)
	}
	state := State{
		to_engine_time(min_value.? or_else {0, 0, 0, 0}),
		to_engine_time(max_value.? or_else {23, 59, 59, 999_999_999}),
	}
	return {generate, new_clone(state), label_of("hegel_odin.times")}
}

// Naive (timezone-free) date-times in `[min_value, max_value]`, shrinking
// towards 2000-01-01T00:00:00.
date_times :: proc(min_value: Maybe(datetime.DateTime) = nil, max_value: Maybe(datetime.DateTime) = nil) -> Generator(datetime.DateTime) {
	State :: struct {
		lo, hi: lh.Datetime,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> datetime.DateTime {
		s := (^State)(data)
		out: lh.Datetime
		check(tc, lh.generate_datetime(tc._ctx, tc._handle, s.lo, s.hi, &out))
		return {date = from_engine_date(out.date), time = from_engine_time(out.time)}
	}
	lo := min_value.? or_else {date = {1, 1, 1}}
	hi := max_value.? or_else {date = {9999, 12, 31}, time = {23, 59, 59, 999_999_999}}
	state := State{
		{to_engine_date(lo.date), to_engine_time(lo.time)},
		{to_engine_date(hi.date), to_engine_time(hi.time)},
	}
	return {generate, new_clone(state), label_of("hegel_odin.date_times")}
}

/*
UUIDs. With a `version`, its version and RFC 4122 variant bits are set;
otherwise all 128 bits are random, except the nil UUID is never produced.
*/
uuids :: proc(version: Maybe(u8) = nil) -> Generator(uuid.Identifier) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> uuid.Identifier {
		version, has_version := (^Maybe(u8))(data).?
		if has_version && version > 15 {
			usage_error(tc, "uuids: version must be in [0, 15], got %d", version)
		}
		out: [16]u8
		check(tc, lh.generate_uuid(tc._ctx, tc._handle, version, has_version, &out))
		return uuid.Identifier(out)
	}
	return {generate, new_clone(version), label_of("hegel_odin.uuids")}
}

ipv4_addresses :: proc() -> Generator(net.IP4_Address) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> net.IP4_Address {
		out: [4]u8
		check(tc, lh.generate_ipv4(tc._ctx, tc._handle, &out))
		return net.IP4_Address(out)
	}
	return {generate, nil, label_of("hegel_odin.ipv4_addresses")}
}

ipv6_addresses :: proc() -> Generator(net.IP6_Address) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> net.IP6_Address {
		out: [16]u8
		check(tc, lh.generate_ipv6(tc._ctx, tc._handle, &out))
		return transmute(net.IP6_Address)out
	}
	return {generate, nil, label_of("hegel_odin.ipv6_addresses")}
}

// IPv4 or IPv6 addresses, shrinking towards IPv4.
ip_addresses :: proc() -> Generator(net.Address) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> net.Address {
		if draw_index(tc, 2) == 0 {
			return draw(tc, ipv4_addresses())
		}
		return draw(tc, ipv6_addresses())
	}
	return {generate, nil, label_of("hegel_odin.ip_addresses")}
}

@(private)
to_engine_date :: proc(d: datetime.Date) -> lh.Date {
	return {i32(d.year), u8(d.month), u8(d.day)}
}

@(private)
from_engine_date :: proc(d: lh.Date) -> datetime.Date {
	return {i64(d.year), i8(d.month), i8(d.day)}
}

@(private)
to_engine_time :: proc(t: datetime.Time) -> lh.Time {
	return {u8(t.hour), u8(t.minute), u8(t.second), u32(t.nano)}
}

@(private)
from_engine_time :: proc(t: lh.Time) -> datetime.Time {
	return {i8(t.hour), i8(t.minute), i8(t.second), i32(t.nanosecond)}
}
