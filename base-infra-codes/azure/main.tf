
################################################################################################################################
# Resource Group Creation
################################################################################################################################

resource "azurerm_resource_group" "app-rg" {
  count    = 2
  name     = "pod${var.pod_number}-app${count.index + 1}-rg"
  location = var.location
}

#########################################################################################################################
# Virtual Network and Subnet Creation
#########################################################################################################################

resource "azurerm_virtual_network" "app-vnet" {
  count               = 2
  name                = "pod${var.pod_number}-app${count.index + 1}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.app-rg["${count.index}"].name
  address_space       = count.index == 0 ? local.vn_cidr1 : local.vn_cidr2
}

resource "azurerm_subnet" "app-subnet" {
  count                = 2
  name                 = "pod${var.pod_number}-app${count.index + 1}-subnet"
  resource_group_name  = azurerm_resource_group.app-rg["${count.index}"].name
  virtual_network_name = azurerm_virtual_network.app-vnet["${count.index}"].name
  address_prefixes     = count.index == 0 ? local.subnet_cidr1 : local.subnet_cidr2
}

################################################################################################################################
# Route Table Creation and Route Table Association
################################################################################################################################

resource "azurerm_route_table" "app_rt" {
  count               = 2
  name                = "pod${var.pod_number}-app${count.index + 1}-rt"
  location            = var.location
  resource_group_name = azurerm_resource_group.app-rg["${count.index}"].name
}

resource "azurerm_subnet_route_table_association" "app_rta" {
  count          = 2
  depends_on     = [azurerm_route_table.app_rt, azurerm_subnet.app-subnet]
  subnet_id      = azurerm_subnet.app-subnet["${count.index}"].id
  route_table_id = azurerm_route_table.app_rt["${count.index}"].id
}

################################################################################################################################
# Keypairs
################################################################################################################################

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

resource "azurerm_ssh_public_key" "rg1-keypair" {
  name                = "pod${var.pod_number}-keypair"
  resource_group_name = azurerm_resource_group.app-rg[0].name
  location            = var.location
  public_key          = tls_private_key.key_pair.public_key_openssh
}

################################################################################################################################
# Virtual Machines
################################################################################################################################

resource "azurerm_linux_virtual_machine" "app" {
  count                 = 2
  name                  = "pod${var.pod_number}-app${count.index + 1}"
  resource_group_name   = azurerm_resource_group.app-rg["${count.index}"].name
  location              = var.location
  size                  = "Standard_B1s"
  admin_username        = "ubuntu"
  network_interface_ids = [azurerm_network_interface.app-interface["${count.index}"].id]

  admin_ssh_key {
    username   = "ubuntu"
    public_key = tls_private_key.key_pair.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  custom_data = count.index == 0 ? base64encode(data.template_file.application1_install.rendered) : base64encode(data.template_file.application2_install.rendered)

  provisioner "file" {
    source      = "./images/azure-app${count.index + 1}.png"
    destination = "/home/ubuntu/azure-app.png"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.key_pair.private_key_openssh
      host        = azurerm_public_ip.app-ip["${count.index}"].ip_address #aws_eip.app-EIP["${count.index}"].public_ip
    }
  }

  provisioner "file" {
    source      = "./html/index.html"
    destination = "/home/ubuntu/index.html"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.key_pair.private_key_openssh
      host        = azurerm_public_ip.app-ip["${count.index}"].ip_address #aws_eip.app-EIP["${count.index}"].public_ip
    }
  }

  provisioner "file" {
    source      = "./html/status${count.index + 1}"
    destination = "/home/ubuntu/status"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.key_pair.private_key_openssh
      host        = azurerm_public_ip.app-ip["${count.index}"].ip_address
    }
  }
  tags = {
    Name = "pod${var.pod_number}-app${count.index + 1}"
  }
}

################################################################################################################################
# Network Security Group Creation
################################################################################################################################

resource "azurerm_network_security_group" "allow-all" {
  count               = 2
  name                = "pod${var.pod_number}-app${count.index + 1}-sg"
  location            = var.location
  resource_group_name = azurerm_resource_group.app-rg["${count.index}"].name

  security_rule {
    name                       = "TCP-Allow-All"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Outbound-Allow-All"
    priority                   = 1002
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*" #var.source_address
    destination_address_prefix = "*"
  }
}

################################################################################################################################
# Network Interface Creation, Public IP Creation and Network Security Group Association
################################################################################################################################

resource "azurerm_public_ip" "app-ip" {
  count               = 2
  name                = "pod${var.pod_number}-app${count.index + 1}-public-ip"
  location            = var.location
  sku                 = "Standard"
  resource_group_name = azurerm_resource_group.app-rg["${count.index}"].name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "app-interface" {
  depends_on          = [azurerm_subnet.app-subnet]
  count               = 2
  name                = "pod${var.pod_number}-app${count.index + 1}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.app-rg["${count.index}"].name

  ip_configuration {
    name                          = "pod${var.pod_number}-app${count.index + 1}-nic-ip"
    subnet_id                     = azurerm_subnet.app-subnet["${count.index}"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = count.index == 0 ? local.app1_nic : local.app2_nic
    public_ip_address_id          = azurerm_public_ip.app-ip["${count.index}"].id
  }
}

resource "azurerm_network_interface_security_group_association" "app-nsg" {
  count                     = 2
  network_interface_id      = azurerm_network_interface.app-interface["${count.index}"].id
  network_security_group_id = azurerm_network_security_group.allow-all["${count.index}"].id
}

################################################################################################################################
# Data Blocks
################################################################################################################################

data "template_file" "application1_install" {
  template = file("${path.module}/application1_install.tpl")
}

data "template_file" "application2_install" {
  template = file("${path.module}/application2_install.tpl")
}

################################################################################################################################
# Locals
################################################################################################################################

locals {
  vn_cidr1     = ["10.${var.pod_number}.0.0/16"]
  vn_cidr2     = ["10.${var.pod_number + 100}.0.0/16"]
  subnet_cidr1 = ["10.${var.pod_number}.100.0/24"]
  subnet_cidr2 = ["10.${var.pod_number + 100}.100.0/24"]
  app1_nic     = "10.${var.pod_number}.100.10"
  app2_nic     = "10.${var.pod_number + 100}.100.10"
}

##################################################################################################################################
# Outputs
##################################################################################################################################

output "app1-public-ip" {
  value = azurerm_public_ip.app-ip[0].ip_address
}

output "app2-public-ip" {
  value = azurerm_public_ip.app-ip[1].ip_address
}

output "app1-private-ip" {
  value = "10.${var.pod_number}.100.10"
}

output "app2-private-ip" {
  value = "10.${var.pod_number + 100}.100.10"
}

output "Command_to_use_for_ssh_into_app1_vm" {
  value = "ssh -i pod${var.pod_number}-private-key ubuntu@${azurerm_public_ip.app-ip[0].ip_address}"
}

output "Command_to_use_for_ssh_into_app2_vm" {
  value = "ssh -i pod${var.pod_number}-private-key ubuntu@${azurerm_public_ip.app-ip[1].ip_address}"
}

output "http_command_app1" {
  value = "http://${azurerm_public_ip.app-ip[0].ip_address}"
}

output "http_command_app2" {
  value = "http://${azurerm_public_ip.app-ip[1].ip_address}"
}