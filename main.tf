# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

# Variable - Input
variable "tag" {
  type        = string
  description = "Created by"
}

variable "region" {
  type        = string
  default     = "eastus"
  description = "Target location"
}

# Create a resource group if it doesn't exist
resource "azurerm_resource_group" "rg_azure_k3d" {
  name     = "rg_azure_k3d"
  location = var.region
  tags = {
    created_by = var.tag
  }
}

# Create virtual network
resource "azurerm_virtual_network" "vn_azure_k3d" {
  name                = "vn_azure_k3d"
  address_space       = ["10.0.0.0/16"]
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_azure_k3d.name
  tags = {
    created_by = var.tag
  }
}

# Create subnet
resource "azurerm_subnet" "sn_azure_k3d" {
  name                 = "sn_azure-k3d"
  resource_group_name  = azurerm_resource_group.rg_azure_k3d.name
  virtual_network_name = azurerm_virtual_network.vn_azure_k3d.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IPs
resource "azurerm_public_ip" "ip_azure_k3d" {
  name                         = "ip_azure_k3d"
  location                     = var.region
  resource_group_name          = azurerm_resource_group.rg_azure_k3d.name
  allocation_method            = "Dynamic"
  sku                          = "Basic"
  domain_name_label            = lower("azure-k3d-${var.tag}")
  tags = {
    candidate = var.tag
  }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "sg_azure_k3d" {
  name                = "sg_azure_k3d"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg_azure_k3d.name
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = {
    created_by = var.tag
  }
}

# Create network interface
resource "azurerm_network_interface" "ni_azure_k3d" {
  name                      = "ni_azure_k3d"
  location                  = var.region
  resource_group_name       = azurerm_resource_group.rg_azure_k3d.name
  ip_configuration {
    name                          = "ip_azure_k3d"
    subnet_id                     = azurerm_subnet.sn_azure_k3d.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip_azure_k3d.id
  }
  tags = {
    created_by = var.tag
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "attach" {
  network_interface_id      = azurerm_network_interface.ni_azure_k3d.id
  network_security_group_id = azurerm_network_security_group.sg_azure_k3d.id
}

# Create SSH key
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

output "vm_key" {
  value       = tls_private_key.ssh_key.private_key_pem
  description = "Virtual machine SSH key"
  sensitive   = true
}

output "vm_dns" {
  value       = "${azurerm_public_ip.ip_azure_k3d.domain_name_label}.${azurerm_public_ip.ip_azure_k3d.location}.cloudapp.azure.com"
  description = "Virtual machine DNS"
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "vm_azure_k3d" {
  name                  = "vm_azure_k3d"
  location              = var.region
  resource_group_name   = azurerm_resource_group.rg_azure_k3d.name
  network_interface_ids = [azurerm_network_interface.ni_azure_k3d.id]
  size                  = "Standard_D2s_v3"
  os_disk {
    name                 = "azure_k3d"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  computer_name                   = "azure-k3d"
  admin_username                  = "devops"
  disable_password_authentication = true
  admin_ssh_key {
    username    = "devops"
    public_key  = tls_private_key.ssh_key.public_key_openssh
  }
  tags = {
    created_by = var.tag
  }
}

# Script
resource "azurerm_virtual_machine_extension" "script" {
  name                 = "challenge_${var.tag}"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm_azure_k3d.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"
  settings = <<SETTINGS
    {
      "commandToExecute": "sh install_k3d.sh"
    }
SETTINGS
}
