[Читать на русском](README_RU.md)

# Azuriom CMS Automatic Installer (English)

This repository contains a script to fully automate the installation and configuration of [Azuriom CMS](https://azuriom.com/) on a **clean Ubuntu 20.04 or 22.04 server**.

<br>

> [!CAUTION]
> ## CRITICAL SECURITY WARNING
>
> **This script is NOT secure and contains known critical vulnerabilities.**
>
> * **Path Traversal:** The script allows bypassing the domain validation (`Continue? (y/N)`). A malicious input like `domain.com/../../etc` **WILL cause catastrophic system damage** by changing permissions on critical system folders.
> * **Command Injection:** The PHP version input is not correctly sanitized before being used in `systemctl` commands. A malicious input like `8.3; reboot` **WILL execute arbitrary commands as root**.
>
> **DO NOT run this script on any server you care about.** It is provided for educational or personal testing purposes **ONLY**, by users who fully understand and accept these risks.

---

## Key Features

* **Full Automation:** Installs the complete web stack and Azuriom CMS with minimal user input.
* **Interactive Setup:** Asks for your domain, email (for SSL), and desired PHP version (8.1, 8.2, 8.3).
* **Full LEMP Stack:** Installs Nginx, MySQL, and PHP-FPM from the stable `ppa:ondrej/php` repository.
* **Security-First Configuration:**
    * **`ufw` Firewall:** Configures the firewall to allow only SSH, HTTP, and HTTPS.
    * **`fail2ban`:** Installs and enables `fail2ban` to protect against brute-force attacks (especially on SSH).
    * **`unattended-upgrades`:** Configures automatic installation of system security updates.
    * **MySQL Hardening:** Secures the `root` user and creates a dedicated, isolated database user for Azuriom.
* **Free SSL (HTTPS):** Automatically installs `certbot` and attempts to obtain a free SSL certificate from Let's Encrypt, including a forced redirect to HTTPS.
* **Secure Password Generation:** Automatically creates strong, unique passwords for the MySQL `root` user and the Azuriom database.
* **Credential Storage:** Saves all generated passwords and DB info to `/root/azuriom_credentials.txt`.

---

## What's Installed (The Stack)

This script will install and configure the following components on your server:

* **Web Server:** `Nginx`
* **Database:** `MySQL Server`
* **PHP:** `PHP-FPM` (Choice of 8.1, 8.2, 8.3 via `ppa:ondrej/php`)
    * **Required Extensions:** `mysql`, `bcmath`, `xml`, `curl`, `zip`, `mbstring`, `tokenizer`, `ctype`, `gd`
* **PHP Manager:** `Composer`
* **SSL:** `Certbot` (from Let's Encrypt)
* **Security:**
    * `UFW` (Firewall)
    * `Fail2Ban`
    * `Unattended-Upgrades` (Auto-updates)
* **CMS:** `Azuriom` (Version detected by the script, or `v1.2.7` as a fallback)

---

## Requirements

To use this script, you need:

1.  A **"clean", disposable Ubuntu server** (20.04 or 22.04 LTS recommended).
2.  A **domain name** with an **A-record** pointed to your server's IP address.
3.  **Root** or `sudo` access.

---

## Usage

1.  Connect to your server via SSH.
2.  Download the English script:
    ```bash
    wget [https://raw.githubusercontent.com/CUTEknopka123/azuriom-ubuntu-installer/main/azuriom_ENG.sh](https://raw.githubusercontent.com/CUTEknopka123/azuriom-ubuntu-installer/main/azuriom_ENG.sh)
    ```

3.  Make the script executable:
    ```bash
    chmod +x azuriom_ENG.sh
    ```
4.  Run the script as root (at your own risk):
    ```bash
    sudo ./azuriom_ENG.sh
    ```
5.  Answer the prompts for your domain, email, and PHP version. The rest is automatic.

---

## After Installation

1.  **Open your domain** in a web browser (`https://your-domain.com`).
2.  You will see the Azuriom web installer. Follow the on-screen instructions.
3.  When the installer asks for database details, get them from the file on your server:
    ```bash
    sudo cat /root/azuriom_credentials.txt
    ```
4.  **Save these credentials in a safe place!** This file contains your MySQL `root` password.
