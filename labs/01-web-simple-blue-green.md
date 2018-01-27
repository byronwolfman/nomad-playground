# Web: Simple Blue Green Labs

**Question** How does one safely update a running webapp to a new version with zero downtime?

This is secretly two questions:

1. How do we ensure the new version is healthy before it receives traffic?
1. How do we ensure that the old version is drained of traffic before we shut it off?

## Preparation

Start the lab by ensuring that no other nomad jobs are running:

```
[root@localhost vagrant]# nomad status
No running jobs
```

If there are any jobs, clean them up:

```
[root@localhost vagrant]# nomad status
ID                               Type            Priority  Status   Submit Date
webapp-cron                      batch/periodic  50        running  01/27/18 15:48:00 UTC
webapp-cron/periodic-1517068140  batch           50        dead     01/27/18 15:49:00 UTC
webapp-poller                    service         50        running  01/27/18 15:48:07 UTC

[root@localhost vagrant]# for JOB in $(nomad job status | cut -d' ' -f1) ; do nomad stop -purge $JOB ; done
...
```

## Lab

We're going to make use of two different Nomad features to check all of our requirements: canaries and shutdown delays. To watch these in action, you'll need a few more console sessions inside the VM:

1. One session running `watch docker ps`
1. One session running `watch dig webapp.service.consul SRV @127.0.0.1 -p 8600 +short`
1. One session running `watch nomad status webapp-web`


With those in view, execute `nomad run job-files/web.nomad` and keep an eye on the other windows.

Ok, what's going on here?

The `docker ps` session is telling you when the containers themselves launch, which should be almost instantaneous. The `dig` session is telling you when those webapps become registered in the Consul catalog. Finally, the `nomad status` session shows you Nomad's worldview as container allocations become placed, started, and eventually healthy. When all allocations are healthy, the deployment is considered to be successful.

Now update the jobspec file with the following change:

```
     task "web" {
       driver = "docker"
       config {
-        image = "webapp:0.1"
+        image = "webapp:0.2"
```

Now execute `nomad run job-files/web.nomad` again and watch the other three sessions carefully.

A couple interesting things happen here: first of all, we now have six running containers (three from our last deploy, three from this one). As with the previous deploy, our new containers are registered into the Consul catalog one-by-one. Also like last time, Nomad show the containers coming online but this time it seems stuck. Have a look at the status:

```
Latest Deployment
ID          = 20a8de13
Status      = running
Description = Deployment is running but requires promotion
```

Hmm, how do we promote this thing?

Pretty easily, as it turns out. Nomad doesn't just have the concept of jobs (mutable things which can be updated) but also deployments, which track these changes. Maybe we'll look at deployments more closely another time; for now, just know that we need to tell nomad to promote the job based on the deployment ID it gave us (in the above example it is `20a8de13`).

While still watching the three other sessions, run `nomad deployment promote 20a8de13` (substituting your deployment ID, which will be different). You'll have to wait about 30 seconds to see the full results, so be patient!

The order of operations will have been very different this time around: first, three containers were de-registered from Consul immediately (the old version 0.1 containers). However, the `docker ps` session showed these to still be running, and the `nomad status` session showed the old containers with a desired state of `stop` but an actual status of `running`. Then about 30 seconds later the old containers stopped and disappeared from `docker ps`.

## Justifications

### Canaries

At the beginning of the lab we said we would use the canaries feature. By itself, if we specified `canaries = 1` then this would mean that a new container would be started with the new code, and then once healthy, would await operator promotion. If promoted, Nomad would then continue with its normal deployment cadence, which is a rolling deploy where it stops a container, starts a container, stops a container, starts a container, all the way until it's done (not necessarily one at a time, but at a rate of `max_parallel` which is 1 by default).

Rolling deploys may be desirable in some cases. If a task group has a very low count to begin with though, then we end up directing a lot of traffic to the remaining containers. By specifying `canary = 3` where the task group also has `count = 3` we are telling Nomad that all containers with the new code must be launched, and healthy, before promotion can even be considered. In other words, a blue-green deploy.

### Shutdown Delays

The other feature we said we would use is shutdown delays. By default, Nomad will stop all containers belonging to the previous version as soon as we promote the new version. This may be undesirable if we have traffic in-flight, or if we use consul-template to update load balancer configs, and those updates may not propagate instantaneously.

By setting `shutdown_delay = "30s"` we tell Nomad to, well, delay! When the new version is promoted, it is removed from the Consul catalog immediately. This means that no new traffic will be sent to the old containers, while still allowing any in-flight traffic to finish what it's doing. This is why the containers disappeared from the catalog immediately but remained running in `docker ps` and `nomad status` for a little while longer.

## Further Experimentation

Try switching back and forth between version 0.1 and 0.2 with the following changes:

* Set `canary = 1`
* Completely remove `canary` option
* Set a shorter `shutdown_delay` (switch versions twice for the full effect)
* Completely remove the `shutdown_delay` option (switch versions twice for the full effect)
* With the `canary` option removed, try setting `count = 6` and `max_parallel = 3` (switch versions twice for the full effect)
* Replace `/shinatra.sh` with `/slow_shinatra.sh`, which takes longer to become healthy
* With `/slow_shinatra.sh` try experimenting with different `min_healthy_time` and `healthy_deadline`

Version 0.3 is broken and will always fail its healthcheck. Set everything back to default in the jobspec file, run a deployment, and then try the following changes:

* Try deploying version 0.3
* Remove `auto_revert = true` and try again

Afterwards, run `nomad deployment list` -- what do you notice that's different? On the surface, nothing is terribly different; the first deployment failed and we "rolled back." The second deployment also failed, but even though we didn't roll back, the state seems unchanged. Why?

To find out, play with `auto_revert` being present or absent while also playing with the `canary` option (different values, present, absent, etc).

## Advanced

"Wait a minute" I hear you saying, "manual promotion? I thought this was DevOps!"

Nomad agents are in fact API servers; the CLI's job is just to interact with that API. You can look inside yourself:

```
[root@localhost vagrant]# curl -Ss localhost:4646/v1/job/webapp-web/deployment | python -m json.tool
{
    "CreateIndex": 392,
    "ID": "1b9cd23a-c1bc-53a6-8378-7c3778c40b52",
    ...
    ...
}

[root@localhost vagrant]# curl -Ss localhost:4646/v1/deployment/promote/1b9cd23a-c1bc-53a6-8378-7c3778c40b52 \
  -X POST \
  --data '{"DeploymentID": "1b9cd23a-c1bc-53a6-8378-7c3778c40b52", "All": true}' \
  | python -m json.tool
{
    "DeploymentModifyIndex": 419,
    ...
}
```

### Further Reading

[Jobspec update stanza](https://www.nomadproject.io/docs/job-specification/update.html)
[Jobspec task shutdown_delay](https://www.nomadproject.io/docs/job-specification/task.html#shutdown_delay)
[Jobs HTTP API](https://www.nomadproject.io/api/jobs.html)
[Deployments HTTP API](https://www.nomadproject.io/api/deployments.html)
