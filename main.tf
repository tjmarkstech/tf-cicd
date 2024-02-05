locals {
  vm_name = "${var.prefix}-vm"
}

############################################################################################
# RESOURCE_GROUP CONFIGURATION
############################################################################################
resource "azurerm_resource_group" "tj_rgroup" {
  name     = "${var.prefix}-resources"
  location = var.location
}

############################################################################################
# VIRTUAL_NETWORK CONFIGURATION
############################################################################################
resource "azurerm_virtual_network" "tj_terraform_vnet" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.tj_rgroup.location
  resource_group_name = azurerm_resource_group.tj_rgroup.name
}

############################################################################################
# SUBNET CONFIGURATION
############################################################################################
resource "azurerm_subnet" "public" {
  name                 = "public"
  resource_group_name  = azurerm_resource_group.tj_rgroup.name
  virtual_network_name = azurerm_virtual_network.tj_terraform_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

############################################################################################
# NETWORK_INTERFACE CONFIGURATION
############################################################################################
resource "azurerm_network_interface" "tj_terraform_network_interface" {
  name                = "${var.prefix}-nic"
  location            = azurerm_resource_group.tj_rgroup.location
  resource_group_name = azurerm_resource_group.tj_rgroup.name

  ip_configuration {
    name                          = "public"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ubuntu-vm-ip.id
  }

  depends_on = [
    azurerm_virtual_network.tj_terraform_vnet,
    azurerm_public_ip.ubuntu-vm-ip
  ]
}

############################################################################################
# STATIC_PUBLIC IP CONFIGURATION
############################################################################################
# Get a Static Public IP
resource "azurerm_public_ip" "ubuntu-vm-ip" {
  depends_on          = [azurerm_resource_group.tj_rgroup]
  name                = "ubuntu-vm-ip"
  location            = azurerm_resource_group.tj_rgroup.location
  resource_group_name = azurerm_resource_group.tj_rgroup.name
  allocation_method   = "Static"
}

############################################################################################
# VIRTUAL_MACHINE CONFIGURATION
############################################################################################
resource "azurerm_virtual_machine" "terraform_vm" {
  name                  = "${var.prefix}-vm"
  location              = azurerm_resource_group.tj_rgroup.location
  resource_group_name   = azurerm_resource_group.tj_rgroup.name
  network_interface_ids = [azurerm_network_interface.tj_terraform_network_interface.id]
  vm_size               = "Standard_D8s_v4"
  #   admin_username                   = "azureuser"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_os_disk {
    name              = "terraform_vm_os_disk"
    caching           = "ReadOnly"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  os_profile {
    computer_name  = var.computer_name
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

}

############################################################################################
# DATA_DISK CONFIGURATION
############################################################################################
resource "azurerm_managed_disk" "tj_terraform_data_disk" {
  name                 = "${local.vm_name}-disk1"
  location             = azurerm_resource_group.tj_rgroup.location
  resource_group_name  = azurerm_resource_group.tj_rgroup.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 256
}

resource "azurerm_virtual_machine_data_disk_attachment" "tj_terraform_data_disk_att" {
  managed_disk_id    = azurerm_managed_disk.tj_terraform_data_disk.id
  virtual_machine_id = azurerm_virtual_machine.terraform_vm.id
  lun                = "0"
  caching            = "ReadOnly"
}


# Create Security Group to access ubuntu
resource "azurerm_network_security_group" "ubuntu_terraform_nsg" {
  depends_on          = [azurerm_resource_group.tj_rgroup]
  name                = "ubuntu_terraform-vm-nsg"
  location            = azurerm_resource_group.tj_rgroup.location
  resource_group_name = azurerm_resource_group.tj_rgroup.name

  security_rule {
    name                       = "Allow_SSH"
    description                = "Allow_SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow_tj"
    description                = "Allow_tj"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "10500-10540"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "Allow_ATS"
    description                = "Allow_ATS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "11111-11119"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

}

# Associate the Ubuntu NSG with the subnet
resource "azurerm_subnet_network_security_group_association" "ubuntu_vm-nsg-association" {
  depends_on                = [azurerm_resource_group.tj_rgroup]
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.ubuntu_terraform_nsg.id
}

