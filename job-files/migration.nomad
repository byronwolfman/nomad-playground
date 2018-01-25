job "webapp-migration" {

  datacenters = ["dc1"]
  type = "batch"

  group "migration" {
    count = 1
    restart {
      attempts = 0
      mode = "fail"
    }

    task "migration" {
      driver = "docker"
      config {
        image = "webapp:0.1"
        command = "/migration.sh"
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
