# Simple Batches / One-Offs Labs

**Question** How does one configure a one-off job?

Up until now we've been using the `service` scheduler which is designed for process that are meant to run indefinitely. We've observed how Nomad treats services that crash: it restarts them. Sometimes though, you want to run something to completion just once, and then move on with your life.

Example use cases: database migrations that run ahead of app deploys; pre- and post-deploy hooks, ad-hoc rake tasks.

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

### Part 1: Multiple (but non-simultaneous) Invocations

While it seems like there can't be that many corner-cases around a one-off dispatch, we can probably find a couple of surprises. To watch the scheduler in action, you'll need a couple more console sessions inside the VM:

1. One session running `watch docker ps`
1. One session running `watch nomad status webapp-migration`

With those in view, execute `nomad run job-files/migration.nomad` and keep an eye on the other windows.

Something is missing! Nomad has no concept of a healthy or unhealthy batch job; a running batch job is always considered healthy until it stops, at which point it has either completed, failed, or become lost. In the above example, the job should complete after 30 seconds.

Without making any changes to the jobspec file, run `nomad run job-files/migration.nomad` again. _Nothing happens._ All tasks in this job have already run to completion, so Nomad shrugs; there's nothing left to do. Open up the jobspec file and make the following change:

```
-    task "migration" {
+    task "migration-1" {
       driver = "docker"
       config {
         image = "webapp:0.1"
```

Now run `nomad run job-files/migration.nomad` again; the batch job will run again. If you rever the change, you can re-run the batch job again! It seems that if you want to run a batch job more than once, you'll need to change the jobspec file in some way. Incrementing the task with a unix timestamp is one method; is there another? Yep:

```
       env {
+        INVOCATION = "1234"
         SOME_VAR = "SOME_VALUE"
       }
```


Run the job to completion, then update `INVOCATION` and run it again. Long story short: Nomad will not run the same batch job twice, so you'll have to modify the jobspec file to convince Nomad to re-run it.

### Part 2: In-flight Changes

The migration batch job takes 30 seconds to run, which is more than enough time for us to modify it while it's still running. Let's do that. Before proceeding, be sure to update `INVOCATION` to a new value.

Invoke `nomad run job-files/migration.nomad` and, quickly update the jobspec file, and then immediately run it again:

```
     task "migration" {
       driver = "docker"
       config {
-        image = "webapp:0.1"
+        image = "webapp:0.2"
         command = "/migration.sh"
       }
```

If done quickly enough, you'll see the `nomad status` is setting the desired state of the previous invocation to `stop`. Sure enough the batch job is stopped prematurely, after which point the replacement job starts. This is because at the very top of the jobspec file is the `job` stanza itself, which is unique within the scheduler. If you want to run two of the same batch jobs simultaneously, you'll need to give them different names (or put another way: when you give it a different name, it's _not the same batch job anymore_).

An easy way to view this is with the `nomad plan` command. If you change something inside the job (such as the `INVOCATION` variable) you'll see something like this:

```
[root@localhost vagrant]# nomad plan job-files/migration.nomad
+/- Job: "webapp-migration"
+/- Task Group: "migration" (1 create, 12 ignore)
  +/- Task: "migration" (forces create/destroy update)
    +/- Env[INVOCATION]: "12345" => "12346"
```

Change the job name itself though, and instead you'll see:

```
[root@localhost vagrant]# nomad plan job-files/migration.nomad
+ Job: "webapp-migration-new"
+ Task Group: "migration" (1 create)
  + Task: "migration" (forces create)
```

Batch jobs should not be considered "fire and forget" but rather another type of work to be scheduled. If Nomad thinks the batch job as-is was already completed in its previous invocation, it will refuse to reschedule it.

### Part 3: Failure

So far we've been using well-behaved batch jobs. Let's change that.

Update the jobspec file:

```
     task "migration" {
       driver = "docker"
       config {
-        image = "webapp:0.1"
+        image = "webapp:0.3"
         command = "/migration.sh"
       }
```

Then run it: `nomad run job-files/migration.nomad`

Whoops. This one fails-- it exits with a return code of 1. Try running it again, unmodified for another surprise: Nomad schedules it! When working with a job that ran to successful completion, we had to modify that jobspec file to run it more than once. A failure doesn't count, so you can run it as often as you want _until it succeeds_. By the way, there's no `auto_revert` option here; the `update` stanza as a whole is disallowed for batch jobs.

Batch jobs don't have to die the moment they fail though. Our `restart` stanza has `attempts = 0` and `mode = "fail"`, so no attempt will be made to rescue the job if it fails the first time. Sometimes restarting will be desirable, and sometimes the job should just back off rather than fail.


## Justifications

Certain choices have been made to mimic a one-off job that might run alongside an app deployment (in this case, a database migration). It's for this reason that the `restart` stanza opts out of any attempt at recovery.

If this isn't just any ad-hoc job, but one that needs to be run with every deployment, then the job needs to be modified in some manner in every deployment. Setting an environment variable to an incrementing serial value or a unix datestamp is a good straightforward way of doing this.

## Further Experimentation

While switching back and forth between version 0.1 and 0.2 (or making any minor change):

* Set `count = 2`
* With `count = 2`, set `command = "echo"` and below that add `args = ["${NOMAD_ALLOC_INDEX}"]`
  * Run `nomad logs replace-with-alloc-id` against the completed allocations
* Set `count` even higher and repeat
* Does setting increasing the count from 1 to 3 run all 3 jobs, or just the difference of 2?
* With `count = 2` set `command = "sh"` and below that use `args = ["-c", "sleep 1 && exit ${NOMAD_ALLOC_INDEX}"]`
  * Run this again; does the scheduler attempt to re-run both containers, or just one?

Rever the jobspec file to default, then switch to version 0.3 and:

* Set `attempts = 1`
* Set `mode = "delay"`
* Adjust some more!
* Specify a non-default `interval` and `delay` in the `restart` stanza

### Further Reading

* [Batch Scheduler](https://www.nomadproject.io/docs/runtime/schedulers.html#batch)
* [Job Interpolation](https://www.nomadproject.io/docs/runtime/interpolation.html)
