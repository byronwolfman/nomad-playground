job "webapp-cron" {

  datacenters = ["dc1"]
  type = "batch"
  
  periodic {
    cron = "* * * * * *"
    prohibit_overlap = true
  }

  group "cron" {

    count = 1
    restart {
      attempts = 10
      interval = "5m"
      delay = "10s"
      mode = "fail"
    }

    task "cron" {
      driver = "docker"
      config {
        image = "webapp:0.1"
        command = "/cron.sh"
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
