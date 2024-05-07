provider "google" {
  project = "project-id"
  region  = "us-central1"
  zone    = "us-central1-c"
}

# Create a Cloud Pub/Sub topic for receiving data from Google News API
resource "google_pubsub_topic" "news_topic" {
  name = "news-topic"
}

# Create a subscription for the Pub/Sub topic
resource "google_pubsub_subscription" "news_subscription" {
  name  = "news-subscription"
  topic = google_pubsub_topic.news_topic.id
}

# Create a storage bucket 
resource "google_storage_bucket" "bucket" {
  name     = "test-bucket"
  location = "US"
}
# Create a storage bucket object
resource "google_storage_bucket_object" "archive" {
  name   = "index.zip"
  bucket = google_storage_bucket.bucket.name
  source = "" #path to zip file
}

# Create a Cloud Function to process incoming data and send it to Vertex AI
resource "google_cloudfunctions_function" "process_news_data" {
  name                   = "process-news-data"
  runtime                = "nodejs16"
  source_archive_bucket  = google_storage_bucket.bucket.name
  source_archive_object  = google_storage_bucket_object.archive.name
  entry_point            = "processNewsData" 
  trigger_http           = true

  environment_variables = {
    PROJECT_ID  = "project_id"
  }
}
###############################################################
#Vertex AI part needs refining 
# Create a Vertex AI Endpoint to deploy the model
resource "google_vertex_ai_endpoint" "news_model_endpoint" {
  display_name  = "news-model-endpoint"
}

# Create a Vertex AI Model
resource "google_vertex_ai_model" "news_model" {
  display_name        = "news-model"
  artifact_uri        = "" #bucket path of trained_model
  serving_container {
    image_uri         = "gcr.io/cloud-aiplatform/prediction/tf2-cpu.2-2:latest"
  }
}

# Deploy the model to the Endpoint
resource "google_vertex_ai_model_deployment" "news_model_deployment" {
  endpoint_id        = google_vertex_ai_endpoint.news_model_endpoint.id
  model_id           = google_vertex_ai_model.news_model.id
}
############################################################################
# Create a BigQuery dataset for storing extracted data
resource "google_bigquery_dataset" "news_dataset" {
  dataset_id                  = "news_dataset"
  friendly_name               = "test"
  description                 = "This is a test description"
  location                    = "US"
  default_table_expiration_ms = 3600000

  labels = {
    env  = "default"
  }

  access {
    role          = "OWNER"
    user_by_email = google_service_account.bqowner.email
  }

}

# Create a BigQuery table for storing extracted data
resource "google_bigquery_table" "news_table" {
  dataset_id = google_bigquery_dataset.news_dataset.dataset_id
  table_id   = "news_table"
  labels     = {
        env  = "default"
  }
  schema {
    fields {
      name = "title"
      type = "STRING"
    }
    fields {
      name = "content"
      type = "STRING"
    }
    # fields can be added as needed
  }
}

# Create a Cloud Function to process data and insert into BigQuery
resource "google_cloudfunctions_function" "insert_into_bigquery" {
  name                   = "insert-into-bigquery"
  description            = "Process data ingestion to Bigquery"
  runtime                = "nodejs16"
  source_archive_bucket  =  google_storage_bucket.bucket.name
  source_archive_object  = google_storage_bucket_object.archive.name
  entry_point            = "insertIntoBigQuery"
  trigger_http           = true

  environment_variables = {
    PROJECT_ID  = "project_id"
    DATASET_ID  = google_bigquery_dataset.news_dataset.dataset_id
    TABLE_ID    = google_bigquery_table.news_table.table_id
  }
}

# Create a Cloud Function to send extracted data to mail listing
resource "google_cloudfunctions_function" "send_to_mail" {
  name                  = "send-to-mail"
  runtime               = "nodejs16"
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.archive.name
  entry_point           = "sendToMail"
  trigger_http          = true

  environment_variables = {
    MAIL_LIST           = "example@lukka.com"
  }
}

# Create a PostgreSQL database
resource "google_sql_database" "postgresql_database" {
  name     = "news_database"
  instance = google_sql_database_instance.postgresql_instance.name
}

# Create a PostgreSQL instance
resource "google_sql_database_instance" "postgresql_instance" {
  name             = "postgresql-instance"
  database_version = "POSTGRES_13"
  region           = "us-central1"
  settings {
    tier = "db-f1-micro"
  }
    deletion_protection  = "true" 
}
########################################################################
# # Create a PostgreSQL user
# resource "google_sql_user" "postgresql_user" {
#   name     = "news_user"
#   instance = google_sql_database_instance.postgresql_instance.name
#   password = "your-password"
# }
#######################################################################