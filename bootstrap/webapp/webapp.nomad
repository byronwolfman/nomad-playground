job "webapp" {

  datacenters = ["dc1"]
  type = "service"

  update {
    max_parallel = 1
    min_healthy_time = "5s"
    healthy_deadline = "1m"
    auto_revert = true
    canary = 3
  }

  group "web" {

    count = 3
    restart {
      attempts = 10
      interval = "5m"
      delay = "10s"
      mode = "delay"
    }

    task "WEBYALL" {
      driver = "docker"
      config {
        image = "webapp:0.1"
        command = "/shinatra.sh"
        port_map {
          http = 8080
        }
      }

      shutdown_delay = "30s"

      env {
        SOME_VAR = "SOME_VALUE"
      }

      resources {
        cpu    = 100 # 100 MHz
        memory = 50 # 50MB
        network {
          mbits = 10
          port "http" {}
        }
      }

      service {
        name = "webapp"
        tags = ["webapp", "web"]
        port = "http"
        check {
          name     = "healthcheck"
          type     = "http"
          port     = "http"
          path     = "/"
          interval = "15s"
          timeout  = "5s"
        }
      }
    }
  }
}
