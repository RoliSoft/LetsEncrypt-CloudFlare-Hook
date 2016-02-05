# LetsEncrypt-CloudFlare-Hook

Implements a hook script for [LetsEncrypt.sh](https://github.com/lukas2511/letsencrypt.sh) which can use the [CloudFlare API](https://api.cloudflare.com/) to set the challenge tokens for the specified domain names in the certificates when the `dns-01` verification type is used.

## Usage

Configure CloudFlare authentication in the script by uncommenting and specifying the `$CF_AUTH_USR` and `$CF_AUTH_KEY` variables within `hook.sh`. Alternatively, leave them commented and export them before calling the `hook.sh` or `letsencrypt.sh` scripts, like so:

	export CF_AUTH_USR="example@example.com"; export CF_AUTH_KEY="1234567893feefc5f0q5000bfo0c38d90bbeb"

In order to use the hook script with the ACME client, you will have to specify `dns-01` as the verification type and the path to the script:

	./letsencrypt.sh -t dns-01 -k hook.sh ...

You can also set the verification type and the path to the script in `config.sh`.