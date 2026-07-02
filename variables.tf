variable "project_id" {
  description = "GCP project ID where the infrastructure will be deployed."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for virtual machines."
  type        = string
  default     = "us-central1-a"
}

variable "name_prefix" {
  description = "Prefix used for all resource names."
  type        = string
  default     = "tf-traffic-project"
}

variable "machine_type" {
  description = "Small VM type to optimize cost."
  type        = string
  default     = "e2-micro"
}

variable "main_traffic_weight" {
  description = "Traffic percentage sent to the production service."
  type        = number
  default     = 100

  validation {
    condition     = var.main_traffic_weight >= 0 && var.main_traffic_weight <= 100
    error_message = "main_traffic_weight must be between 0 and 100."
  }
}

variable "contingency_traffic_weight" {
  description = "Traffic percentage sent to the contingency service."
  type        = number
  default     = 0

  validation {
    condition     = var.contingency_traffic_weight >= 0 && var.contingency_traffic_weight <= 100
    error_message = "contingency_traffic_weight must be between 0 and 100."
  }
}
