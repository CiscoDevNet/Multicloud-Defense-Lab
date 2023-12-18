provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
   subscription_id = "b1fef409-33f5-4600-9671-959924983d2f"
}

