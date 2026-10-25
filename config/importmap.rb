# Pin npm packages by running ./bin/importmap

# A module loaded from a CDN carries its own integrity hash, as the layouts'
# Bootstrap and Mermaid tags do: the browser refuses the file if a compromised
# CDN or package serves anything else. Local pins are same-origin assets and
# stay unhashed. NIST SI-7 (software integrity), SR-11.
enable_integrity!

pin "application", integrity: false
pin "@hotwired/turbo-rails", to: "turbo.min.js", integrity: false
pin "@hotwired/stimulus", to: "stimulus.min.js", integrity: false
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", integrity: false
pin_all_from "app/javascript/controllers", under: "controllers", integrity: false

# Cropper.js for avatar crop/scale/center (#234). The hash is of the file both
# jsdelivr and npm's published 1.6.2 tarball serve (dist/cropper.esm.js).
pin "cropperjs", to: "https://cdn.jsdelivr.net/npm/cropperjs@1.6.2/dist/cropper.esm.js",
                 integrity: "sha384-wGjZOvKnL9JWxMY59NPk+NqPOzE99IQINJQ/BMG3eKO5/fHvWf0+nfyTSUnaKuKm"
