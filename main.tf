resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.name_prefix}-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_firewall" "allow_lb_http" {
  name    = "${var.name_prefix}-allow-lb-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = ["${var.name_prefix}-web"]
}

resource "google_compute_instance" "main_service" {
  name         = "${var.name_prefix}-main-vm"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["${var.name_prefix}-web"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash
    mkdir -p /opt/traffic-service

    cat > /opt/traffic-service/server.py <<'PYTHON'
    from http.server import BaseHTTPRequestHandler, HTTPServer

    MESSAGE = "Bienvenido al Servicio Principal - Versión Producción"
    TITLE = "Servicio Principal"

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            body = f"""<!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>{TITLE}</title>
    </head>
    <body>
      <h1>{MESSAGE}</h1>
    </body>
    </html>
    """.encode("utf-8")

            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            return

    HTTPServer(("0.0.0.0", 80), Handler).serve_forever()
    PYTHON

    cat > /etc/systemd/system/traffic-service.service <<'SERVICE'
    [Unit]
    Description=Terraform traffic demo service
    After=network-online.target

    [Service]
    ExecStart=/usr/bin/python3 /opt/traffic-service/server.py
    Restart=always

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable traffic-service
    systemctl restart traffic-service
  SCRIPT
}

resource "google_compute_instance" "contingency_service" {
  name         = "${var.name_prefix}-contingency-vm"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["${var.name_prefix}-web"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash
    mkdir -p /opt/traffic-service

    cat > /opt/traffic-service/server.py <<'PYTHON'
    from http.server import BaseHTTPRequestHandler, HTTPServer

    MESSAGE = "Error 503 - Sitio en Mantenimiento Programado"
    TITLE = "Servicio de Contingencia"

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            body = f"""<!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <title>{TITLE}</title>
    </head>
    <body>
      <h1>{MESSAGE}</h1>
    </body>
    </html>
    """.encode("utf-8")

            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            return

    HTTPServer(("0.0.0.0", 80), Handler).serve_forever()
    PYTHON

    cat > /etc/systemd/system/traffic-service.service <<'SERVICE'
    [Unit]
    Description=Terraform traffic demo service
    After=network-online.target

    [Service]
    ExecStart=/usr/bin/python3 /opt/traffic-service/server.py
    Restart=always

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable traffic-service
    systemctl restart traffic-service
  SCRIPT
}

resource "google_compute_instance_group" "main_group" {
  name = "${var.name_prefix}-main-group"
  zone = var.zone

  instances = [
    google_compute_instance.main_service.id
  ]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_instance_group" "contingency_group" {
  name = "${var.name_prefix}-contingency-group"
  zone = var.zone

  instances = [
    google_compute_instance.contingency_service.id
  ]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_health_check" "http" {
  name = "${var.name_prefix}-http-health-check"

  http_health_check {
    port_specification = "USE_SERVING_PORT"
    request_path       = "/"
  }
}

resource "google_compute_backend_service" "main_backend" {
  name                  = "${var.name_prefix}-main-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.http.id]
  session_affinity      = "NONE"

  backend {
    group           = google_compute_instance_group.main_group.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_backend_service" "contingency_backend" {
  name                  = "${var.name_prefix}-contingency-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.http.id]
  session_affinity      = "NONE"

  backend {
    group           = google_compute_instance_group.contingency_group.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "url_map" {
  name = "${var.name_prefix}-url-map"

  default_route_action {
    weighted_backend_services {
      backend_service = google_compute_backend_service.main_backend.id
      weight          = var.main_traffic_weight
    }

    weighted_backend_services {
      backend_service = google_compute_backend_service.contingency_backend.id
      weight          = var.contingency_traffic_weight
    }
  }

  lifecycle {
    precondition {
      condition     = var.main_traffic_weight + var.contingency_traffic_weight == 100
      error_message = "main_traffic_weight and contingency_traffic_weight must add up to 100."
    }
  }
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "${var.name_prefix}-http-proxy"
  url_map = google_compute_url_map.url_map.id
}

resource "google_compute_global_address" "public_ip" {
  name = "${var.name_prefix}-public-ip"
}

resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name                  = "${var.name_prefix}-http-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_proxy.id
  ip_address            = google_compute_global_address.public_ip.id
}
