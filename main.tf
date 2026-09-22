resource "google_project_service" "artifact_registry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

### KMS key auto fetching BLOCK newly added

data "google_project" "current" {
  project_id = var.project_id
}

data "google_kms_key_ring" "project_keyring" {
  project  = var.project_id
  name     = var.project_id
  location = var.location
}

data "google_kms_crypto_key" "project_key" {
  name     = "${data.google_project.current.name}-key"
  key_ring = data.google_kms_key_ring.project_keyring.id
}

### KMS key auto fetching BLOCK newly added

resource "google_project_service_identity" "artifact_registry_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "artifactregistry.googleapis.com"

  depends_on = [google_project_service.artifact_registry]
}

resource "time_sleep" "wait_for_artifact_registry_sa" {
  create_duration = "60s"

  depends_on = [google_project_service_identity.artifact_registry_sa]
}

resource "google_kms_crypto_key_iam_member" "artifact_registry_cmek" {
  crypto_key_id = data.google_kms_crypto_key.project_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"

  depends_on = [time_sleep.wait_for_artifact_registry_sa]

  lifecycle {
    ignore_changes = [member]
  }
}

resource "google_artifact_registry_repository" "artifact-repo" {
  count         = var.no_of_repos
  repository_id = var.name_of_repos[count.index]
  provider      = google-beta
  project       = var.project_id
  location      = var.location
  description   = var.description[count.index] != null ? var.description[count.index] : "testing"
  kms_key_name  = data.google_kms_crypto_key.project_key.id
  format        = var.format
  mode          = var.mode

  docker_config {
    immutable_tags = var.format == "DOCKER" ? true : false
  }

  lifecycle {
    ignore_changes = [labels]
  }

  depends_on = [
    google_kms_crypto_key_iam_member.artifact_registry_cmek
  ]
}

data "google_project" "service_project3" {
  project_id = var.project_id
}