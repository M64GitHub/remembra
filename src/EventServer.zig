//! SSE Event Server - runs in separate thread for real-time event broadcasting.
const std = @import("std");
const Cli = @import("Cli.zig").Cli;

pub const EventServer = struct {
    allocator: std.mem.Allocator,
    connections: std.ArrayList(*Connection),
    mutex: std.Thread.Mutex,
    port: u16,
    running: bool,
    cli: *Cli,

    const Connection = struct {
        stream: std.net.Stream,
        active: bool,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        port: u16,
        cli: *Cli,
    ) EventServer {
        return .{
            .allocator = allocator,
            .connections = .empty,
            .mutex = .{},
            .port = port,
            .running = false,
            .cli = cli,
        };
    }

    pub fn deinit(self: *EventServer) void {
        self.running = false;
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.connections.items) |conn| {
            conn.stream.close();
            self.allocator.destroy(conn);
        }
        self.connections.deinit(self.allocator);
    }

    pub fn run(
        self: *EventServer,
    ) void {
        self.running = true;

        const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, self.port);
        var server = address.listen(.{
            .reuse_address = true,
        }) catch |err| {
            self.cli.msg(
                .err,
                "[EventServer] Failed to listen on port {}: {}\n",
                .{ self.port, err },
            );
            return;
        };
        defer server.deinit();

        self.cli.msg(
            .ok,
            "[EventServer] Listening on port {}\n",
            .{self.port},
        );

        while (self.running) {
            const conn_result = server.accept();
            if (conn_result) |client| {
                self.handleConnection(client.stream) catch |err| {
                    self.cli.msg(
                        .err,
                        "[EventServer] Connection error: {}\n",
                        .{err},
                    );
                };
            } else |_| {
                continue;
            }
        }
    }

    fn handleConnection(self: *EventServer, stream: std.net.Stream) !void {
        var buf: [1024]u8 = undefined;
        _ = stream.read(&buf) catch return;

        const response =
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/event-stream\r\n" ++
            "Cache-Control: no-cache\r\n" ++
            "Connection: keep-alive\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "\r\n";

        stream.writeAll(response) catch return;

        const conn = try self.allocator.create(Connection);
        conn.* = .{
            .stream = stream,
            .active = true,
        };

        self.mutex.lock();
        self.connections.append(self.allocator, conn) catch {
            self.mutex.unlock();
            stream.close();
            self.allocator.destroy(conn);
            return;
        };
        self.mutex.unlock();
    }

    pub fn broadcast(self: *EventServer, event_json: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.connections.items.len) {
            const conn = self.connections.items[i];
            if (!conn.active) {
                conn.stream.close();
                self.allocator.destroy(conn);
                _ = self.connections.swapRemove(i);
                continue;
            }

            conn.stream.writeAll("data: ") catch {
                conn.active = false;
                i += 1;
                continue;
            };
            conn.stream.writeAll(event_json) catch {
                conn.active = false;
                i += 1;
                continue;
            };
            conn.stream.writeAll("\n\n") catch {
                conn.active = false;
                i += 1;
                continue;
            };
            i += 1;
        }
    }

    pub fn connectionCount(self: *EventServer) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.connections.items.len;
    }
};
