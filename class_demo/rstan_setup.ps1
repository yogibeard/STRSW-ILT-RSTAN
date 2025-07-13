# Scritp updated 20250714 RSTAN
# Prompt for root password

$rootPassword = Read-Host -AsSecureString "Enter Lab Default password"
$rootPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($rootPassword))
  
# Define variables
$sshFolder = "$env:USERPROFILE\.ssh"
$keyName = "id_ecdsa"
$linuxHosts = @("centos1", "centos2")
$remoteUser = "root"
$clusters = @("cluster1")  
# Ensure .ssh directory exists
if (-Not (Test-Path -Path $sshFolder)) {
    [void](New-Item -ItemType Directory -Path $sshFolder)
}
  
# Generate SSH key
if (-Not (Test-Path -Path $sshFolder\$keyName)){
ssh-keygen -q -t ecdsa -f "$sshFolder\$keyName" -N '""' 
}

# Copy public key to authorized_keys
$pubKey = Get-Content "$sshFolder\$keyName.pub"
$authKeysPath = "$sshFolder\authorized_keys"
if (-Not (Test-Path -Path $authKeysPath)) {
    [void](New-Item -ItemType File -Path $authKeysPath)
}
Add-Content -Path $authKeysPath -Value $pubKey
  
# Save password to a temporary file
$temp_pw_file = [System.IO.Path]::GetTempFileName()
Set-Content -Path $temp_pw_file -Value $rootPasswordPlain
  

# Copy .ssh folder to Linux machines and set permissions
Write-Host "# Copy .ssh folder to Linux machines and set permissions"

foreach (${linuxHost} in ${linuxHosts}) {
    Write-Output y| plink  -pwfile $temp_pw_file ${remoteUser}@${linuxHost} "mkdir -p ~/.ssh"
    pscp -q -pwfile $temp_pw_file -r $sshFolder ${remoteUser}@${linuxHost}:
    plink -batch -pw ${rootPasswordPlain} ${remoteUser}@${linuxHost} "chmod 700 ~/.ssh; chmod 600 ~/.ssh/id_ecdsa; chmod 600 ~/.ssh/authorized_keys"
}

# Enable publickey authentication for the admin user in the clusters and copy the admin user's public key to each cluster
Write-Host "# Enable publickey authentication for the admin user in the clusters and copy the admin user's public key to each cluster"
$clusters | ForEach-Object {
    $remoteCommand = "security login create -user-or-group-name admin -application ssh -authmethod publickey -role admin ; security login publickey create -username admin -publickey `"`"$pubkey`"`""
    [void](Write-Output -y|plink -batch -pw $rootPasswordPlain admin@$_ $remoteCommand)
}

Write-Host "Assign known_hosts to variable"
$knownHostsPath = "$env:USERPROFILE\.ssh\known_hosts" 

# Add hostkeys of Linux Hosts to known_hosts
Write-Host "# Add hostkeys of Linux Hosts to known_hosts"

foreach ($linuxHost in $linuxHosts) {
    ssh-keyscan -H $linuxHost 2>$null | Out-File -Append -Encoding ascii $knownHostsPath 
}

# Add hostkeys of clusters to known_hosts
Write-Host "# Add hostkeys of clusters to known_hosts"
 
foreach ($cluster in $clusters) {
    ssh-keyscan -H $cluster 2>$null | Out-File -Append -Encoding ascii $knownHostsPath 
}

  
# Copy .ssh/known_hosts to Linux machines
Write-Host "# Copy .ssh/known_hosts to Linux machines"

foreach (${linuxHost} in ${linuxHosts}) {
    scp  -q ${sshFolder}\known_hosts ${remoteUser}@${linuxHost}:~/.ssh/
 }

  
# Create Bash script to prepare the Linux machines
Write-Host "# Create Bash script to prepare the Linux machines"
$bashScript = @'
#!/bin/bash

# echo "Checking CentOS version..."
if grep -q "CentOS Linux release 8" /etc/redhat-release; then

  # Directory containing repo files
  REPO_DIR="/etc/yum.repos.d"
    
  # Loop through all .repo files
  for file in "$REPO_DIR"/*.repo; do
      if grep -q "^failovermethod=" "$file"; then
          echo "Updating $file..."
          # Comment out all lines starting with 'failovermethod='
          sed -i 's/^failovermethod=/# failovermethod=/' "$file"
      fi
      done
      echo "All applicable 'failovermethod' lines have been commented out."
      
      echo "Disabling custom Python 3.11 in /usr/local/bin..."
        
      # Rename or remove custom Python 3.11 binaries
      for bin in /usr/local/bin/python3.11 /usr/local/bin/python3.11-config /usr/local/bin/ansible /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.11; do
          if [ -f "$bin" ]; then
              sudo mv "$bin" "${bin}.disabled"
              echo "Disabled $bin"
          fi
      done
        
        
      # Remove broken symlink
      if [ -L /usr/local/bin/python3 ]; then
        sudo rm -f /usr/local/bin/python3
        echo "Removed broken symlink /usr/local/bin/python3"
      fi
    
  echo "Installing Python 3.9 from AppStream..."
  sudo dnf module enable -y python39
  sudo dnf install -y python39 python39-devel python39-pip
    
  echo "Updating alternatives to make Python 3.9 the default..."
    
  # Register python3.9 with alternatives
  sudo alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 100
  sudo alternatives --set python3 /usr/bin/python3.9
  sudo alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip3.9 100
  sudo alternatives --set pip3 /usr/bin/pip3.9
    
  # Optional: also set 'python' to point to python3.9
  sudo alternatives --install /usr/bin/python python /usr/bin/python3.9 100
  sudo alternatives --set python /usr/bin/python3.9
  sudo alternatives --install /usr/bin/pip pip /usr/bin/pip3.9 100
  sudo alternatives --set pip /usr/bin/pip3.9
    
    
    
  echo "Python version now set to:"
  which python3
  python3 --version
  which python
  python --version
  
fi


if [ "$(hostname)" = "centos1" ]; then
   echo "Running on centos1"

   # Clone the Class Labs Git Repo and setup venv. Install ansible
   
   
   # Exit immediately if a command exits with a non-zero status
   #set -e
   
   # Define the target directory
   TARGET_DIR="$HOME/ansible-workshop"
   
   # Clone the Git repository into the target directory
   echo "Cloning Git repository into $TARGET_DIR..."
   git clone https://github.com/yogibeard/STRSW-ILT-RSTAN.git "$TARGET_DIR"
   
   
   # Navigate to the project directory
   cd "$TARGET_DIR"
   
   # Create a Python virtual environment in the project directory
   echo "Creating Python virtual environment in $TARGET_DIR/.venv..."
   python3 -m venv .venv
   
   # Activate the virtual environment
   source .venv/bin/activate
   
   # Upgrade pip
   echo "Upgrading pip..."
   pip install --upgrade pip
   
   # Install required Python packages
   echo "Installing required packages..."
   pip install ansible ansible-lint jupyter netapp-lib oslo_log bash_kernel nbconvert
   
   # Register the bash kernel with Jupyter
   echo "Registering bash kernel with Jupyter..."
   python -m bash_kernel.install
   
   chmod -R +x /root/.ansible/collections/
   

   # Define the activation line
   ACTIVATION_LINE="source ~/ansible-workshop/.venv/bin/ \n export ANSIBLE_FORCE_COLOR=1 \n export PY_COLORS=1"
   
   # Check if the line already exists in ~/.bashrc
   if grep -Fxq "$ACTIVATION_LINE" ~/.bashrc; then
       echo "Virtual environment activation already present in ~/.bashrc"
   else
       echo -e "\n# Auto-activate Python virtual environment for ansible-workshop\n$ACTIVATION_LINE" >> ~/.bashrc
       
       echo "Added virtual environment activation to ~/.bashrc"
   fi
   
   
   echo "Setup complete. Virtual environment is ready in $TARGET_DIR/.venv"
fi
'@
  
# Save Bash script to a file
$bashScriptPath = "$env:TEMP\setup_linux.sh"
Set-Content -Path "$bashScriptPath" -Value "$bashScript"


# Create Post Install Bash script to prepare the Linux machines
Write-Host "# Create Post Install Bash script to prepare the Linux machines"


# Copy and execute the Bash script on Linux Hosts
Write-Host "# Copy and execute the Bash script on Linux Hosts" 
foreach ($linuxHost in $linuxHosts) {
  scp -q $bashScriptPath ${remoteUser}@${linuxHost}:~/setup_linux.sh
  ssh ${remoteUser}@${linuxHost} "dos2unix -q ~/setup_linux.sh"
  ssh ${remoteUser}@${linuxHost} "chmod +x ~/setup_linux.sh"
  ssh ${remoteUser}@${linuxHost} "~/setup_linux.sh"
  ssh ${remoteUser}@${linuxHost} "rm -f ~/setup_linux.sh"
}

$post_install = @'
#!/bin/bash
#Insert any commands as required for post install, here...
'@

# Save Post Install Bash script to a file
$post_installPath = "$env:TEMP\post_linux.sh"
Set-Content -Path "$post_installPath" -Value "$post_install"

# Copy and execute the Bash script on Linux Hosts
Write-Host "# Copy and execute the Bash script on Linux Hosts" 
foreach ($linuxHost in $linuxHosts) {
  #ssh ${remoteUser}@${linuxHost} "mkdir -p ~/cifsad"  
  scp -q $post_installPath ${remoteUser}@${linuxHost}:~/post_linux.sh
  ssh ${remoteUser}@${linuxHost} "dos2unix -q ~/post_linux.sh"
  ssh ${remoteUser}@${linuxHost} "chmod +x ~/post_linux.sh"
}


# Clean up temporary password file
Remove-Item -Path $temp_pw_file
Remove-Item -Path $bashScriptPath
Remove-Item -Path $post_installPath

# Define paths
$installerPath = "$env:TEMP\vscode.exe"
$codeCmd = "$env:USERPROFILE\AppData\Local\Programs\Microsoft VS Code\bin\code.cmd"
  
# Check if VS Code is already installed
if (-Not (Test-Path $codeCmd)) {
    Write-Host "VS Code not found. Downloading and installing..."
  
    # Download VS Code installer
    Invoke-WebRequest -Uri "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user" -OutFile $installerPath
  
    # Install VS Code silently without launching it after installation
    Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT /MERGETASKS=!runcode" -Wait
  
    # Wait until the CLI becomes available
    while (-not (Test-Path $codeCmd)) {
        Start-Sleep -Seconds 2
    }
  
    Write-Host "VS Code installed successfully."
} else {
    Write-Host "VS Code is already installed. Skipping download and installation."
}
  
# Download VSIX for Remote SSH extension
$remoteSshVsixPath = "$env:TEMP\remote-ssh.vsix"
Invoke-WebRequest -Uri "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-vscode-remote/vsextensions/remote-ssh/latest/vspackage" -OutFile $remoteSshVsixPath
  
# Install the Remote SSH extension
& $codeCmd --install-extension $remoteSshVsixPath
 

