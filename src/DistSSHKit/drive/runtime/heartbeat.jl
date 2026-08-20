# Drive worker heartbeat: one deadline. No pong from the master for `deadline`
# seconds and the worker leaves. Matches SSH ServerAlive ~600s (see remote.jl).

function _heartbeat_config(env=ENV)
    interval = something(tryparse(Float64, get(env, "DISTRIBUTED_HEARTBEAT_INTERVAL_SEC", "30")), 30.0)
    deadline = something(tryparse(Float64, get(env, "DISTRIBUTED_HEARTBEAT_DEADLINE_SEC", "600")), 600.0)
    interval > 0 || (interval = 30.0)
    deadline > 0 || (deadline = 600.0)
    return (; interval, deadline)
end

_master_alive(last_pong::Real, deadline::Real, now::Real=time()) = (now - last_pong) <= deadline

"""Prober + watchdog. `ping` / `clock` / `on_dead` are injectable. At most one in-flight ping."""
function _run_heartbeat!(
    stop::Ref{Bool},
    interval,
    deadline;
    ping=() -> remotecall_fetch(() -> true, 1),
    clock=time,
    on_dead=() -> exit(0),
)
    last_pong = Ref(clock())
    prober = @async while !stop[]
        try
            ping()
            last_pong[] = clock()
        catch
        end
        stop[] && break
        sleep(interval)
    end
    watchdog = @async while !stop[]
        sleep(interval)
        stop[] && break
        _master_alive(last_pong[], deadline, clock()) || (on_dead(); break)
    end
    return (; prober, watchdog, last_pong)
end
