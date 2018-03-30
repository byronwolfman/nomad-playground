# Simple Crons

**Question** How does one schedule, update, and manage cron jobs in Nomad?

Periodic jobs have a surprising number of gotchas horizontally-scaled systems. There are matters of concurrency to think about, both in terms of when a job is initially invoked, and how it is tracked. Nomad tries to solve this problem with the `periodic` stanza, which creates a sort of metajob -- a job that schedules _other jobs_.

Let' see what that looks like.

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

### Part 1: Overlaps and Updates

Overlapping and non-overlapping jobs are easy to conceptualize about, but it's fun to watch in action. You'll need a few more console sessions inside the VM to see how these behave:

1. One session running `watch docker ps`
1. One session running `watch nomad status`
1. One session running `watch nomad status webapp-cron`

With those in view, execute `nomad run job-files/cron.nomad` and keep an eye on the other windows.

You can see what I mean by "metajob"! The `nomad status` session shows you the job you submitted which have the `batch/periodic` type, and the resulting jobs that it has fired off which are plain 'ol `batch` jobs.

```
ID                               Type            Priority  Status   Submit Date
webapp-cron                      batch/periodic  50        running  02/04/18 21:11:51 UTC
webapp-cron/periodic-1517778720  batch           50        dead     02/04/18 21:12:00 UTC
webapp-cron/periodic-1517778900  batch           50        dead     02/04/18 21:15:00 UTC
webapp-cron/periodic-1517779080  batch           50        running  02/04/18 21:18:00 UTC
```

You may notice that these jobs are happening three minutes apart, even though the jobspec file specifies `cron = "* * * * * *"`. This is because we also specified `prohibit_overlap = true` and our pretend cron job happens to last 2 minute and 30 seconds. Note that when a job is already running, Nomad does not schedule the next invocation to happen at the completion of the first job; instead the invocation is ignored completely and Nomad starts counting down to the next invocation.

This is likely by design to prevent an unlimited number of jobs being queued, and isn't so bad for frequently-executed jobs. Some extra care may be needed when designing jobs with longer periods, such as daily or weekly jobs.

Anyway let's change that:

```
   periodic {
     cron = "* * * * * *"
-    prohibit_overlap = true
   }
```

Run it again with `nomad run job-files/cron.nomad`, ideally while a batch job is already in-progress. You'll notice that updating the `periodic` controller doesn't stop or otherwise affect the batch job in progress. After all, we're not modifying the batch job, but the underlying periodic job that controls them. Also, in a few minutes we'll have a lot of overlapping jobs. Revert the jobspec file before things get too out of control:


```
   periodic {
     cron = "* * * * * *"
+    prohibit_overlap = true
   }
```

Run `nomad run job-files/cron.nomad` to get us back to normal.

### Part 2: Failure

Update the jobspec file:

```
     task "cron" {
       driver = "docker"
       config {
-        image = "webapp:0.1"
+        image = "webapp:0.3"
         command = "/cron.sh"
       }
```

As you may know from other labs, version 0.3 is always broken in some manner. Whereas this pretend cron normally takes 2 minutes and 30 seconds to return an exit code of 0, version 0.3 will "crash" by returning an exit code of 1 after 10 seconds. Run `nomad run job-files/cron.nomad` and keep an eye on the other sessions.

Uh oh.

After a minute, you should notice the the latest job from the `nomad status` sessions hasn't changed. Its status has remained `running` through out. This is because the container which keeps dying is being scheduled not by the `webapp-cron` periodic job, but by the `webapp-cron/periodic-1234567890` job that it spawned. Almost all of the stanzas in the jobspec file are passed to the spawned job; they're not for the periodic job itself. Apart from syntactical problems, it's not really possible to present a misconfigured `periodic` job, because a periodic job is nothing more than what's inside the `periodic` stanza itself -- the rest is passed on.

Our `restart` stanza specifies `mode = "fail"` so after the cron fails to launch, the spawned job gives up. Note that the periodic controller itself makes no distinction between whether its spawned job has succeeded or failed; both are given the status "dead." You can get additional detail from the spawned job itself though since there is technically nothing special about it. Run `nomad job status webapp-cron/periodic-1234567890` (replacing the actual job name with some from your `nomad status` session) and these will describe a more complete outcome of "complete" vs "failed."

### Part 3: Failure Forever

Incidentally, it's possible to change the `restart` stanza so that `mode = "delay"` instead, but this is probably a bad idea if you have also set `prohibit_overlap = true`. A job that always fails and is rescheduled forever will never complete, and will consequently block new invocations forever.

Since these are experimental labs though, let's try it. Set `mode = "delay"` and `prohibit_overlap = true`, execute with the usual `nomad run job-files/cron.nomad`. Once the new spawned job starts, revert the config back to `image = "webapp:0.1" and try to update the periodic job with `nomad run job-files/cron.nomad`. Now minimize your sessions and go work on something else for the next half hour. Sure enough when you come back, the scheduler will still be trying (unsuccessfully) to run the 0.3 cron, and the working 0.1 will still be waiting for the next invocation.

All is not lost though. You're still ops, and you can put an end to it just as you would a normal job. Invoke `nomad stop webapp-cron/periodic-1234567890` (replacing the actual job name with whichever one is running non-stop). When the next minute rolls around, version 0.1 will finally start.

## Justifications

For the `periodic` stanza itself there are no hard and fast rules. Sometimes you don't want overlapping jobs, sometimes you do. Plan accordingly.

The more important choice is what you do with the `restart` stanza. Generally speaking `mode = "fail"` seems a more robust choice since the [Halting Problem](https://en.wikipedia.org/wiki/Halting_problem) is hard enough without conceding even further ground.

## Further Experimentation

There's a lot more to explore with crons! Unlike most other labs, you won't have to switch between version 0.1 and 0.2 to see the effect of your changes. Feel free to stay on version 0.1 (unless otherwise specified) while adjusting other parameters. Try:

* Set `count = 2`
* With `count = 2` set `command = "sh"` and below that use `args = ["-c", "sleep 1 && exit ${NOMAD_ALLOC_INDEX}"]`
  * How many containers get re-scheduled? What counts for the sake of overlap?

### Further Reading

* [Batch Scheduler](https://www.nomadproject.io/docs/runtime/schedulers.html#batch)
* [Periodic Stanza](https://www.nomadproject.io/docs/job-specification/periodic.html)
* [The Halting Problem](https://en.wikipedia.org/wiki/Halting_problem)
