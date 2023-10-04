variable "aws_access_key" {}

variable "aws_secret_key" {}

variable "region" {
  type    = string
  default = "us-east-1"
}
variable "pod_number" {
  type = number
}