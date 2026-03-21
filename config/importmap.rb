# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Cropper.js for avatar crop/scale/center (#234)
pin "cropperjs", to: "https://cdn.jsdelivr.net/npm/cropperjs@1.6.2/dist/cropper.esm.js"
