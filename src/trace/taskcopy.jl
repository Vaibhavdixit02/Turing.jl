if is_unix() libpath = replace(@__FILE__, "src/trace/taskcopy.jl", "deps/") end
if is_windows() libpath = replace(@__FILE__, "src\\trace\\taskcopy.jl", "deps\\") end

if !(libpath in Base.DL_LOAD_PATH)
  push!(Base.DL_LOAD_PATH, libpath)
end
# println(libpath)

# Utility function for self-copying mechanism
n_copies() = n_copies(current_task())
n_copies(t::Task) = begin
  isa(t.storage, Void) && (t.storage = ObjectIdDict())
  if haskey(t.storage, :n_copies)
    t.storage[:n_copies]
  else
    t.storage[:n_copies] = 0
  end
end

function Base.copy(t::Task)
  t.state != :runnable && t.state != :done &&
    error("Only runnable or finished tasks can be copied.")
  newt = ccall((:jl_clone_task, "libtask"), Any, (Any,), t)::Task
  if t.storage != nothing
    n = n_copies(t)
    t.storage[:n_copies]  = 1 + n
    newt.storage = copy(t.storage)
  else
    newt.storage = nothing
  end
  newt.code = t.code
  newt.state = t.state
  newt.result = t.result
  newt.parent = t.parent
  newt.storage[:turing_chnl] = deepcopy(t.storage[:turing_chnl]) # Channel(0);
  newt.storage[:turing_chnl].putters[1] = newt
  push!(newt.storage[:turing_chnl].takers, current_task())
  bind(newt.storage[:turing_chnl], newt)
  if istaskstarted(t)
      schedule(newt);
      newt.state = :queued
  end
  if :last in fieldnames(t)
    newt.last = nothing
  end
  newt
end

@suppress_err function Base.produce(v)
  #### un-optimized version
  #q = current_task().consumers
  #t = shift!(q.waitq)
  #empty = isempty(q.waitq)
  ct = current_task()
  local empty, t, q
  while true
    q = ct.consumers
    if isa(q,Task)
      t = q
      ct.consumers = nothing
      empty = true
      break
    elseif isa(q,Condition) && !isempty(q.waitq)
      t = shift!(q.waitq)
      empty = isempty(q.waitq)
      break
    end
    wait()
  end

  t.state = :runnable
  if empty
    if isempty(Base.Workqueue)
      yieldto(t, v)
    else
      Base.schedule_and_wait(t, v)
    end
    ct = current_task() # When a task is copied, ct should be updated to new task ID.
    while true
      # wait until there are more consumers
      q = ct.consumers
      if isa(q,Task)
        return q.result
      elseif isa(q,Condition) && !isempty(q.waitq)
        return q.waitq[1].result
      end
      wait()
    end
  else
    schedule(t, v)
    # make sure `t` runs before us. otherwise, the producer might
    # finish before `t` runs again, causing it to see the producer
    # as done, causing done(::Task, _) to miss the value `v`.
    # see issue #7727
    yield()
    return q.waitq[1].result
  end
end
