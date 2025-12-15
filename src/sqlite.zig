//! Minimal SQLite3 C API wrapper.

pub const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const SqliteDb = struct {
    db: *c.sqlite3,

    pub fn open(path: [*:0]const u8) !SqliteDb {
        var db_ptr: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path, &db_ptr);
        if (rc != c.SQLITE_OK) {
            if (db_ptr) |p| _ = c.sqlite3_close(p);
            return error.SqliteOpenFailed;
        }
        return .{ .db = db_ptr.? };
    }

    pub fn close(self: *SqliteDb) void {
        _ = c.sqlite3_close(self.db);
    }

    pub fn exec(self: *SqliteDb, sql: [*:0]const u8) !void {
        var err_msg: [*c]u8 = null;
        const rc = c.sqlite3_exec(self.db, sql, null, null, &err_msg);
        if (rc != c.SQLITE_OK) {
            if (err_msg != null) c.sqlite3_free(err_msg);
            return error.SqliteExecFailed;
        }
    }

    pub fn prepare(self: *SqliteDb, sql: [*:0]const u8) !*c.sqlite3_stmt {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SqlitePrepareFailed;
        return stmt.?;
    }

    pub fn lastInsertRowId(self: *SqliteDb) i64 {
        return c.sqlite3_last_insert_rowid(self.db);
    }
};

pub fn finalize(stmt: *c.sqlite3_stmt) void {
    _ = c.sqlite3_finalize(stmt);
}

pub fn step(stmt: *c.sqlite3_stmt) c_int {
    return c.sqlite3_step(stmt);
}

pub fn reset(stmt: *c.sqlite3_stmt) void {
    _ = c.sqlite3_reset(stmt);
}

pub fn bindInt(stmt: *c.sqlite3_stmt, col: c_int, val: c_int) void {
    _ = c.sqlite3_bind_int(stmt, col, val);
}

pub fn bindInt64(stmt: *c.sqlite3_stmt, col: c_int, val: i64) void {
    _ = c.sqlite3_bind_int64(stmt, col, val);
}

pub fn bindDouble(stmt: *c.sqlite3_stmt, col: c_int, val: f64) void {
    _ = c.sqlite3_bind_double(stmt, col, val);
}

pub fn bindText(stmt: *c.sqlite3_stmt, col: c_int, txt: []const u8) void {
    _ = c.sqlite3_bind_text(stmt, col, txt.ptr, @intCast(txt.len), null);
}

pub fn bindNull(stmt: *c.sqlite3_stmt, col: c_int) void {
    _ = c.sqlite3_bind_null(stmt, col);
}

pub fn columnInt(stmt: *c.sqlite3_stmt, col: c_int) c_int {
    return c.sqlite3_column_int(stmt, col);
}

pub fn columnInt64(stmt: *c.sqlite3_stmt, col: c_int) i64 {
    return c.sqlite3_column_int64(stmt, col);
}

pub fn columnDouble(stmt: *c.sqlite3_stmt, col: c_int) f64 {
    return c.sqlite3_column_double(stmt, col);
}

pub fn columnText(stmt: *c.sqlite3_stmt, col: c_int) []const u8 {
    const ptr = c.sqlite3_column_text(stmt, col);
    const len = c.sqlite3_column_bytes(stmt, col);
    if (ptr == null or len <= 0) return "";
    return @as([*]const u8, @ptrCast(ptr))[0..@intCast(len)];
}
