# Simple Pollers Labs

**Question** How does Nomad treat pollers?

Specifically:

1. How does Nomad stop pollers during a rolling update?
1. How does Nomad treat a flaky poller that crashes?

Perhaps better-known as "workers," a poller takes asynchronous work off a queue. [Sidekiq](https://github.com/mperham/sidekiq) and [Celery](https://github.com/celery/celery) are two well-known examples.

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

### Part 1: Rolling Updates

In this lab we're going to watch how pollers when they update, when they fail, and (ideally) when they fail _during_ an update. To watch these in action, you'll need a couple more console sessions inside the VM:

1. One session running `watch docker ps`
1. One session running `watch nomad status webapp-poller`

With those in view, execute `nomad run job-files/poller.nomad` and keep an eye on the other windows. It should execute pretty qucikly! The containers show up in `docker ps` first, but are not considered "healthy" for a few seconds. We'll examine what exactly that means in a moment. First, let's look at a rolling deployment.

Update the jobspec file:

```
     task "poller" {
       driver = "docker"
       config {
-        image = "webapp:0.1"
+        image = "webapp:0.2"
```

Once again execute `nomad run job-files/poller.nomad` and watch the other two sessions. Here's what should have happened:

1. A v0.1 poller was immediately stopped
1. A v0.2 poller was started
1. After 15 seconds, another v0.1 poller was stopped and replaced with a v0.2 poller
1. After 15 seconds more, Nomad delcared the deployment healthy.

This 15 second interval isn't incidental; if you look inside the jobspec file, you'll see `min_healthy_time = "15s"`. In this rolling update we're replacing one container at a time, so there will be a 15 second pause between each. If we're in a hurry, reducing `min_healthy_time` isn't our only option; try setting `max_parallel = 2` and switching back to version 0.1:

```
   update {
-    max_parallel = 1
+    max_parallel = 2
...
...
     task "poller" {
       driver = "docker"
       config {
-        image = "webapp:0.2"
+        image = "webapp:0.1"
```

Run `nomad run job-files/poller.nomad` again and you might notice something a bit scary: Nomad _stops_ both containers before starting the new ones. We could use a canary like we did with the web containers, but arguably this is not as important for a worker taking messages off of a queue. A rolling update is probably "good enough" because it's not serving a synchronous API that needs to always be available.

Speaking of failing...

### Part 2: Rolling Update Failures

Nomad is waiting 15 seconds for these containers to become "healthy" -- but what does that mean for a container that has no HTTP API or any listening socket for that matter? Make the following updates to the jobspec file to find out:

```
   update {
-    max_parallel = 2
-    min_healthy_time = "15s"
+    max_parallel = 1
+    min_healthy_time = "30s"
...
...
     task "poller" {
       driver = "docker"
       config {
-        image = "webapp:0.1"
+        image = "webapp:0.3"
```

To summarize: we're setting `max_parallel` back to 1 to get our rolling updates back; we're setting `min_healthy_time` to 30 seconds for _reasons_ that will become apparent, and most consequentially, we're using version 0.3. If you've read the main README you may recall that versions 0.1 and 0.2 are almost identical, but version 0.3 is always broken.

Let's imagine that someone has checked in some bad code and now the poller crashes shortly after initialization. Run `nomad run job-files/poller.nomad` to watch what happens.

At the end of it all, Nomad's status description will read "Deployment completely successfully" -- but not so fast! If you were watching closely, you'll notice in the `docker ps` window that one of the containers running version 0.1 never stopped, and the newer container has the same image ID. Look closer:

```
[root@localhost ~]# nomad logs -job webapp-poller
polling 0.1...
polling 0.1...
polling 0.1...
...
```

It's still running version 0.1. Look again, this time with the `deployment` command:

```
[root@localhost ~]# nomad deployment list
ID        Job ID         Job Version  Status      Description
6d29ee74  webapp-poller  8            successful  Deployment completed successfully
a980ca64  webapp-poller  7            failed      Failed due to unhealthy allocations - rolling back to job version 6
```

Version 0.3 has a flaw that causes it to exit with a non-zero return code after 15 seconds. Nomad doesn't have a magic way of knowing whether or not a poller is throwing (handled) exceptions. The one thing it will notice: a program that crashes. By setting `min_healthy_time = "30s"` what we're really saying is that the poller is healthy as long as it can execute without exiting for 30 seconds.

We also have `auto_revert = true` which means that when the deployment failed, Nomad automatically re-deployed the previous healthy version of the job. It is this second, automatic deployment that `nomad status` shows as having succeeded, not the version 0.3 update we tried to push.

Finally, `healthy_deadline = "1m"` has a role to play too: regardless of what the `restart` stanza specifies, the version 0.3 poller gets 1 minute _total_ throughout the whole deployment process to start a healthy version of each container in the rolling deploy. If you do the math, the poller crashes every 15 seconds and has a 10 second cool-down between attempts, which is why we see this timeline:

* 0s: poller starts (first attempt)
* 15s: poller fails
* 25s: poller starts (second attempt)
* 40s: poller fails
* 50s: poller starts (third attempt)
* 60s: Nomad rolls back

The actual time will drift by a few seconds since scheduling is not instantaneous. Interestingly, Nomad does not wait for the poller to reach `min_healthy_time` on its third attempt; once the 1 minute mark has been reached it will roll back. I've picked some of these thresholds for lab expediency, but it seems that there should be some care taken in choosing thresholds for production-bound workloads.

### Part 3: Post-Update Failures

Of course, we only detected this failure during the rolling update because of the 30 second `min_healthy_time` threshold. If that threshold were shorter, the poller would have deployed "successfully" but still crashed. Let's see how that's handled. With the the flaky 0.3 code still in the jobspec file, adjust it so that `min_healthy_time = "10s"` and then execute `nomad run job-files/poller.nomad`.

The results are kind of funny, but don't laugh too hard: you could be operating this!

The deployment "succeeds" but the pollers crash over and over again. Eventually around the 5 minute mark (though it may vary based on your system's ability to multitask) Nomad gives up on starting the pollers, and `nomad status` shows them pending. This is the result of the `restart` stanza for the job itself. To prevent non-stop churning, we've told Nomad that it can make up to 10 restart attempts over the course of 10 minutes, with a 10 second delay between each. If we use up all of our attempts before 10 minutes is up, then no more attempts are made until that 10 minute interval passes.

It bears pointing out that the 10 minute countdown begins the first time a restart is issued, not that last one. If you watch the "Created" column in `nomad status` you'll see that once it edges past the 10 minute mark, Nomad begins scheduling containers again. It helps to say it out loud: "don't attempt to restart the container more than 10 times within a 10 minute window."

Anyway, this is obviously bad, so let's revert:

```
   update {
-    min_healthy_time = "10s"
+    min_healthy_time = "15s"
...
...
     task "poller" {
       driver = "docker"
       config {
-        image = "webapp:0.3"
+        image = "webapp:0.1"
```

Run `nomad run job-files/poller.nomad` to get us back to a good place.

### Part 4: Graceful Shutdowns

Have you noticed something about the name of the command? It's `/poller_graceful.sh` because it knows how to handle SIGTERM! Nomad (via Docker) sends containers SIGTERM when it's shutting down an outgoing container (note that Nomad doesn't just schedule containers, and sends a [different signal](https://www.nomadproject.io/docs/operating-a-job/update-strategies/handling-signals.html) in such cases).

Start following the logs with `nomad logs -f -job webapp-poller` and then doing a rolling update from version 0.1 to 0.2. The poller will indicate that it's received SIGTERM and then exit immediately. That's just polite. Not all programs know what to do with SIGTERM though. Now update the jobspec file again because we need to know how an impolite process behaves:

```
     task "poller" {
       driver = "docker"
       config {
-        image = "webapp:0.1"
-        command = "/poller_graceful.sh"
+        image = "webapp:0.2"
+        command = "/poller_impolite.sh"
       }
```

Deploy again with `nomad run job-files/poller.nomad`. At first, nothing should be significantly different. After all, the impolite poller was the one that was _started,_ not _stopped_ with this deploy. Start tailing logs with `nomad logs -f -job webapp-poller` and roll the version between 0.2 and 0.1 again, while watching the `docker ps` and `nomad status` windows as well.

The poller wants to keep going. To be fair, this poller was written to explicitly ignore SIGTERM so that it would be logged. Some apps won't necessarily catch and handle SIGTERM; they'll just keep going without any outward indication. Nomad (or rather, Docker) gives the container 10 seconds to finish whatever it's doing. If it hasn't stopped of its own accord by then, it will send SIGKILL (and SIGKILL means business).

If 10 seconds isn't enough, the [kill_timeout](https://www.nomadproject.io/docs/operating-a-job/update-strategies/handling-signals.html) option allows you to set a longer grace period.

## Justifications

### Rolling Updates

Though previously covered, pollers do not necessarily need a canary the way that API servers do. There's no synchronous traffic to be interrupted, so if polling briefly stops during the update, it won't be the end of the world as long as it resumes shortly, and as long as the workers can catch up.

### Right-sized Thresholds

An appropriately long `min_healthy_time` and short `healthy_deadline` ensures that a poller which can't even initialize itself will be caught, and not left to languish. If it does crash, Nomad will restart it, but at least we know it can initialize. A short `min_healthy_time` may hide a poller that is unable to initialize; a long `healthy_deadline` may allow a bad poller to churn unnecessarily.


## Further Experimentation

Try switching back and forth between version 0.1 and 0.3 with the following changes:

* Remove `auto_revert = true`
* Set `max_parallel = 2` with and without `auto_revert`
* Adjust `healthy_deadline` and `min_healthy_time`
* Set a short `min_healthy_time` so that the bad 0.3 poller "succeeds" and then adjust values in the `restart` stanza
* Set a short `min_healthy_time` so that the bad 0.3 poller "succeeds" and then in the `restart` stanza set `mode = "fail"`

Try switching back and forth between version 0.1 and 0.2 with the following changes:

* Use `/poller_impolite.sh` with a long [kill_timeout](https://www.nomadproject.io/docs/operating-a-job/update-strategies/handling-signals.html)
* Use `/poller_graceful.sh` with a long [kill_timeout](https://www.nomadproject.io/docs/operating-a-job/update-strategies/handling-signals.html)

### Further Reading

* [Jobspec update stanza](https://www.nomadproject.io/docs/job-specification/update.html)
