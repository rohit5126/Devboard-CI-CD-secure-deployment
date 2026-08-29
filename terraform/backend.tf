terraform {
    backend "s3" {
        bucket = "diksha-state-devboard-2003"
        key          = "terraform.tfstate"
        region       = "eu-north-1"
        encrypt      = true
        
        # Enable S3-native state locking
        use_lockfile = true 
    }
}
