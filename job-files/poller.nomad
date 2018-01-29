job "webapp-poller" {

  datacenters = ["dc1"]
  type = "service"

  update {
    max_parallel = 1
    min_healthy_time = "15s"
    healthy_deadline = "1m"
    auto_revert = true
  }

  group "poller" {

    count = 2
    restart {
      attempts = 10
      interval = "10m"
      delay = "10s"
      mode = "delay"
    }

    task "poller" {
      driver = "docker"
      config {
        image = "webapp:0.1"
        command = "/poller_graceful.sh"
      }

      env {
        SOME_VAR = "SOME_VALUE"
      }

      resources {
        cpu    = 100 # 100 MHz
        memory = 50 # 50MB
        network {
          mbits = 10
        }
      }
    }
  }
}
