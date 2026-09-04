# Deploy

`git push` applies updates automatically (cron, every 2 min): config changes
(`.pi/**`) restart pi, container-spec changes rebuild, package-list changes
reinstall packages.

`/root/.pi/agent` is a named docker volume (`pi-agent-home`). It survives
restarts and holds config and runtime state (sessions, npm) in one path. A
bind can't sit on it directly; the mount would wipe the runtime data. The
repo mounts read-only at `/etc/pi-skel`, and the entrypoint copies it into
the volume on each container start:

```sh
cp -r /etc/pi-skel/. /root/.pi/agent/
```

The copy is why restarts pick up repo config: it lands in the volume without
touching runtime state.
