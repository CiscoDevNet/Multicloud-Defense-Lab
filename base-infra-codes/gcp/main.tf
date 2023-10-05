#############################################
# Data Blocks
#############################################

data "template_file" "application1_install" {
  template = file("${path.module}/application1_install.tpl")
}

data "template_file" "application2_install" {
  template = file("${path.module}/application2_install.tpl")
}

#############################################
# Enable required services on the project
#############################################
resource "google_project_service" "service" {
  for_each = toset(var.project_services)
  project  = var.project_id

  service            = each.key
  disable_on_destroy = false
}

##################################################################################################################################
# Service account
##################################################################################################################################

resource "google_service_account" "sa" {
  account_id   = "pod${var.pod_number}-service-account"
  display_name = "pod${var.pod_number}-service-account"
}

#############################################
# Locals
#############################################

locals {
  subnet_cidr1 = "10.${var.pod_number}.100.0/24"
  subnet_cidr2 = "10.${var.pod_number + 100}.100.0/24"
  app1_nic     = "10.${var.pod_number}.100.10"
  app2_nic     = "10.${var.pod_number + 100}.100.10"
}

##################################################################################################################################
# Networks
##################################################################################################################################

resource "google_compute_network" "network" {
  count                   = 2
  name                    = "pod${var.pod_number}-app${count.index + 1}-vpc"
  routing_mode            = "GLOBAL"
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnets" {
  count         = 2
  name          = "pod${var.pod_number}-app${count.index + 1}-subnet"
  ip_cidr_range = count.index == 0 ? local.subnet_cidr1 : local.subnet_cidr2
  network       = google_compute_network.network["${count.index}"].name
}

#################################################################################################################################
# Keypair
#################################################################################################################################

resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.key_pair.private_key_openssh
  filename        = "pod${var.pod_number}-private-key"
  file_permission = 0700
}

resource "local_file" "public_key" {
  content         = tls_private_key.key_pair.public_key_openssh
  filename        = "pod${var.pod_number}-public-key"
  file_permission = 0700
}

#################################################################################################################################
# Instances
#################################################################################################################################


resource "google_compute_instance" "application" {
  count          = 2
  name           = "pod${var.pod_number}-app${count.index + 1}"
  project        = var.project_id
  machine_type   = "e2-micro"
  zone           = var.vm_zones[0]
  can_ip_forward = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = "20"
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnets["${count.index}"].self_link
    network_ip = count.index == 0 ? local.app1_nic : local.app2_nic
    access_config {
      nat_ip       = null
      network_tier = "STANDARD"
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.key_pair.public_key_openssh}"
  }
  metadata_startup_script = count.index == 0 ? data.template_file.application1_install.rendered : data.template_file.application2_install.rendered
  service_account {
    email  = google_service_account.sa.email
    scopes = ["cloud-platform"]
  }
   tags = ["pod${var.pod_number}-app${count.index + 1}"]
}

resource "null_resource" "name" {
  count      = 2
  depends_on = [google_compute_instance.application[0], google_compute_instance.application[1]]

  provisioner "file" {
    source      = "./html/index.html"
    destination = "/home/ubuntu/index.html"
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.key_pair.private_key_openssh
      host        = google_compute_instance.application["${count.index}"].network_interface[0].access_config[0].nat_ip
    }
  }

  triggers = {
    instance_id = google_compute_instance.application["${count.index}"].id
  }
}

resource "null_resource" "name1" {
  count      = 2
  depends_on = [google_compute_instance.application[0], google_compute_instance.application[1]]

  provisioner "file" {
    source      = "./images/gcp-app${count.index + 1}.png"
    destination = "/home/ubuntu/gcp-app.png"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.key_pair.private_key_openssh
      host        = google_compute_instance.application["${count.index}"].network_interface[0].access_config[0].nat_ip
    }
  }


  triggers = {
    instance_id = google_compute_instance.application["${count.index}"].id
  }
}


resource "null_resource" "name2" {
  count      = 2
  depends_on = [google_compute_instance.application[0], google_compute_instance.application[1]]

  provisioner "file" {
    source      = "./html/status${count.index + 1}"
    destination = "/home/ubuntu/status"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.key_pair.private_key_openssh
      host        = google_compute_instance.application["${count.index}"].network_interface[0].access_config[0].nat_ip
    }
  }


  triggers = {
    instance_id = google_compute_instance.application["${count.index}"].id
  }
}

#################################################################################################################################
# Firewall Rules
#################################################################################################################################

resource "google_compute_firewall" "allow-ssh-bastion" {
  count   = 2
  name    = "pod${var.pod_number}-app${count.index+1}-sg"
  network = google_compute_network.network["${count.index}"].name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  source_ranges           = ["35.0.0.0/8" ,"35.235.240.0/20", "172.16.0.0/12", "72.163.0.0/16", "192.133.192.0/19", "64.100.0.0/14","64.100.10.0/23","64.100.12.0/24","64.100.13.0/24","192.133.192.0/23","192.133.202.0/24","64.100.255.0/25","128.107.222.0/24","128.107.219.0/24","128.107.220.0/24","128.107.221.0/24","128.107.93.0/24"]
  target_service_accounts = [google_service_account.sa.email]
}

#################################################################################################################################
# Output
#################################################################################################################################

output "app1-public-ip" {
  value = google_compute_instance.application[0].network_interface[0].access_config[0].nat_ip
}

output "app2-public-ip" {
  value = google_compute_instance.application[1].network_interface[0].access_config[0].nat_ip
}

output "app1-private-ip" {
  value = "10.${var.pod_number}.100.10"
}

output "app2-private-ip" {
  value = "10.${var.pod_number + 100}.100.10"
}


output "Command_to_use_for_ssh_into_app1_vm" {
  value = "ssh -i pod${var.pod_number}-private-key ubuntu@${google_compute_instance.application[0].network_interface[0].access_config[0].nat_ip}"
}

output "Command_to_use_for_ssh_into_app2_vm" {
  value = "ssh -i pod${var.pod_number}-private-key ubuntu@${google_compute_instance.application[1].network_interface[0].access_config[0].nat_ip}"
}

output "http_command_app1" {
  value = "http://${google_compute_instance.application[0].network_interface[0].access_config[0].nat_ip}"
}

output "http_command_app2" {
  value = "http://${google_compute_instance.application[1].network_interface[0].access_config[0].nat_ip}"
}


