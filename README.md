# Nomad Playground

[Nomad](https://www.nomadproject.io/) is a general-purpose application scheduler. I put this repo together so that I could experiment with Nomad's job specifications and poke at its boundaries and answer some questions. What _actually_ happens in a rolling update? At what point are canaries registered with Consul? When are the old processes de-registered? What happens if I roll out a flaky poller?

This repo has everything you need to start answering these questions:

* A Vagrantfile to fire up the test environment with:
  * CentOS 7, as you might find in many businesses
  * Docker CE
  * Consul running in dev mode
  * Nomad running in dev mode
* Some toy "microservices" which are built inside the VM
* Some starter jobspec files

## Quick Start

You'll need [Vagrant](https://www.vagrantup.com/downloads.html) and [VirtualBox](https://www.virtualbox.org/wiki/Downloads) if you don't have them already, but that's it. All other dependencies live inside the VM. Fire it up:

    laptop $ vagrant up

This will take a few minutes as the Vagrantbox installs some software and runs some Ansible. Once bootstrapping is done, enter the VM with:

    laptop $ vagrant ssh

Become root inside the VM and move to the `/vagrant` directory:

    [vagrant@localhost ~]$ sudo -i
    [root@localhost ~]# cd /vagrant

Note that this directory mounts the repo underneath it, so you can make changes to the jobspec files in your favourite editor, and have those changes present inside the VM. Finally, launch a job:

```
[root@localhost vagrant]# nomad run job-files/web.nomad
==> Monitoring evaluation "ac5e4797"
    Evaluation triggered by job "webapp-web"
    ...
    ...
==> Evaluation "ac5e4797" finished with status "complete"
```

Introspect your new containers:

```
[root@localhost vagrant]# nomad status webapp-web

[root@localhost vagrant]# docker ps

[root@localhost vagrant]# consul catalog services -tags

[root@localhost vagrant]# dig +short SRV webapp.service.consul @127.0.0.1 -p 8600
```

## Next Steps

Several guided [labs](https://github.com/byronwolfman/nomad-playground/tree/master/labs) are provided to explore Nomad's scheduling behaviour. These labs make use of an included "webapp" docker image with different executables inside, each mimicking a particular function you might see performed by a microservice:

1. `job-files/web.nomad` launches several web containers. The update stanza is designed to use a blue/green stategy with manual promotion and zero downtime. Watch the Consul catalog and Docker's `ps` during a deploy to see how this is done. Crashed containers should be restarted by Nomad. The "webserver" is actually just netcat; the unmodified version can be found in [this repo](https://github.com/benrady/shinatra).
1. `job-files/poller.nomad` launches pretend poller containers. They don't do anything but occasionally output text to stdout. Think of this as a mock sidekiq or celery. Crashed containers should be restarted by Nomad.
1. `job-files/migration.nomad` uses the batch scheduler to run a single job that, when complete, does not reschedule itself. Unlike the web and poller jobspec files, this one does not attempt to restart itself if it fails.
1. `job-files/cron.nomad` uses the `periodic` stanza to fire off batch jobs at regularly-scheduled intervals. Periodic jobs are interesting because they are jobs that _create other jobs;_ if this seems confusing, try invoking `nomad job status` a few minutes after running this job file. Nomad will attempt to restart a crashed cron job multiple times, but it will eventually give up.

Much of Nomad's behaviour towards misbehaving processes (including the actions described above) are modifiable, which is what this playground is all about! Guided labs are provided in the [labs](https://github.com/byronwolfman/nomad-playground/tree/master/labs) directory but may be ignored in favour of freeform experimentation too.

### Variants

The web jobspec file invokes `/shinatra.sh` but you can also try out `/slow_shinatra.sh`. This version takes a few seconds to "boot up" before it will start returning healthchecks (whereas the not-slow shinatra should become healthy immediately).

The poller jobspec file invokes `/poller_graceful.sh` but you can also try out `/poller_impolite.sh`. Whereas the graceful poller responds to SIGTERM when asked to shut down, the impolite one does not. You can experiment with how Docker and Nomad deal with these.

### Variant Versions

Each jobspec file uses the `webapp:0.1` image by default, invoking a different script inside to mock out the web/poller/migration/cron role. There is also a `webapp:0.2` image which is functionally identical, except that it will specify a different version in the logging output (so you can tell them apart).

There is also `webapp:0.3` where everything is subtly broken: web never becomes healthy, the pollers crash, the crons crash, the migration crashes, you get the idea. This version also includes another web variant, `/flaky_shinatra.sh` which will initially start healthy, and then start throwing HTTP 500 errors after a short time.

These three versions should let you experiment with transitioning between two different working versions (0.1 and 0.2) and a busted version (0.3).

## Internals

The "webapp" containers are all alpine-based to remain as small as possible. None of them perform any actual work (except arguably the web containers).

Ansible is responsible for installing and configuring the underlying services. It does this in a way which is largely _not_ idempotent, so be carefully executing `vagrant provision` after the VM is already launched.

As a related precaution, do not use the playbooks or this repo as a guide to configuring these services in a production or production-like environment. Many production-hardening features have been shut off in the name of speed (namely ACLs and fault-tolerance). This repo's purpose is to provide a throw-away environment to play with jobspec files; the act of configuring and deploying Nomad is left as a sepaerate exercise.
