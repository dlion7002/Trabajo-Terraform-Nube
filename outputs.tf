output "load_balancer_ip" {
  description = "Public IP address of the single entry point."
  value       = google_compute_global_address.public_ip.address
}

output "test_url" {
  description = "URL to test in the browser."
  value       = "http://${google_compute_global_address.public_ip.address}"
}

output "production_weight" {
  description = "Traffic weight for the production service."
  value       = var.main_traffic_weight
}

output "contingency_weight" {
  description = "Traffic weight for the contingency service."
  value       = var.contingency_traffic_weight
}
