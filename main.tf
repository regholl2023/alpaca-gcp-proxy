provider "google" {
  project     = var.project_id
  region      = var.region
}

terraform {
  backend "gcs" {
    bucket  = "n30-tf-state-bucket"
    prefix  = ""
  }
}

variable "slack_notification_url" {
    default = "https://hooks.slack.com/services/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"
}

variable "env" {
    default = "dev"
}

variable "project_id" {
    default = "development-380917"
}

variable "region" {
    default = "us-east4"
}

locals {
  resource_prefix = var.env == "prod" ? "" : "${var.env}-"
}



# --------------------------
# -- Function Storage Bucket
# --------------------------
resource "google_storage_bucket" "serverless_function_bucket" {
  name          = "${local.resource_prefix}serverless-function-bucket"
  location      = "US"
}



# --------------------------
# -- Slack Notifier Function
# --------------------------
data "archive_file" "slack_notifier" {
  type        = "zip"
  output_path = "/tmp/slack_notifier.zip"
  source_dir = "functions/notifier"
}

resource "google_storage_bucket_object" "slack_notifier_zip" {
  name   = "${local.resource_prefix}slack-notifier.zip"
  bucket = google_storage_bucket.serverless_function_bucket.name
  content_type = "application/zip"
  source = data.archive_file.slack_notifier.output_path
  depends_on = [
    google_storage_bucket.serverless_function_bucket
  ]
}

resource "google_cloudfunctions_function" "slack_notifier" {
  name        = "${local.resource_prefix}slack-notifier"
  description = "Slack Notifier Function"
  runtime     = "python311"
  source_archive_bucket = google_storage_bucket.serverless_function_bucket.name
  source_archive_object = google_storage_bucket_object.slack_notifier_zip.name
  trigger_http = true
  entry_point = "slackNotifier"
  available_memory_mb = 128
}

#---------------------------
# -- FRONT END DEPLOYMENT --
#---------------------------

#---------------------------
# -- React Cloud Run      --
#---------------------------
resource "google_cloud_run_service" "default" {
  name     = "cloudrun-react"
  location = "us-east4"

  template {
    spec {
      containers {
        image = "gcr.io/development-380917/react-with-cloudrun"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location    = google_cloud_run_service.default.location
  project     = google_cloud_run_service.default.project
  service     = google_cloud_run_service.default.name

  policy_data = data.google_iam_policy.noauth.policy_data
}