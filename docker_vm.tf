terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.50.0"
    }
  }
}
provider "azurerm" {
  subscription_id = "26d96de7-f44a-499c-8951-bb04330aa5c7"
  features {}
}


#rg
resource "azurerm_resource_group" "rg1" {
  name     = "docker-rg"
  location = "central india"
}

#vnet
resource "azurerm_virtual_network" "vnet1" {
  name                = "docker-vnet"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
  address_space       = ["10.0.0.0/20"]
}

#subnet

resource "azurerm_subnet" "subnet1" {
  name                 = "docker-subnet"
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.0.0.0/26"]
}

#PIP

resource "azurerm_public_ip" "pip" {
  name                = "pip1"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
  allocation_method   = "Static"
}

#NIC

resource "azurerm_network_interface" "nic" {
  name                = "docker-nic"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "docker-vm"
  resource_group_name             = azurerm_resource_group.rg1.name
  location                        = azurerm_resource_group.rg1.location
  size                            = "Standard_D2s_V3"
  admin_username                  = "dockervm"
  admin_password                  = "docker@1234"
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  
custom_data = base64encode(<<EOF
#!/bin/bash
set -e

# wait for apt lock
while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
      fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
  sleep 5
done

apt-get update -y
apt-get install -y docker.io
systemctl enable docker
systemctl start docker
usermod -aG docker dockervm
EOF
)
}

#NSG

resource "azurerm_network_security_group" "nsg1" {
  name                = "nsg1"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location

  security_rule {
    name                       = "docker-security"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22-80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

#NSG association with NIC

resource "azurerm_network_interface_security_group_association" "nic-nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg1.id
}

