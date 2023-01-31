<# ----------------------------------------------------------------------------
Licensed to the Apache Software Foundation (ASF) under one
or more contributor license agreements.  See the NOTICE file
distributed with this work for additional information
regarding copyright ownership.  The ASF licenses this file
to you under the Apache License, Version 2.0 (the
"License"); you may not use this file except in compliance
with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing,
software distributed under the License is distributed on an
"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
KIND, either express or implied.  See the License for the
specific language governing permissions and limitations
under the License.
----------------------------------------------------------------------------#>

<#
.SYNOPSIS
	Apache Maven Wrapper startup PowerShell script, version @@project.version@@
.DESCRIPTION
	Required ENV vars:
	JAVA_HOME - location of a JDK home dir
	
	Optional ENV vars
	MAVEN_BATCH_ECHO - set to 'on' to enable the echoing of the batch commands
	MAVEN_BATCH_PAUSE - set to 'on' to wait for a keystroke before ending
	MAVEN_OPTS - parameters passed to the Java VM when running Maven
		e.g. to debug Maven itself, use
		set MAVEN_OPTS=-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=y,address=8000
	MAVEN_SKIP_RC - flag to disable loading of mavenrc files
.EXAMPLE
     .\mvnw verify
#>

[CmdletBinding()]
Param (
	# Non common paramaters
	[Parameter(mandatory = $false, ValueFromRemainingArguments)]
	$RemainingParameters
)

# useful functions
function Test-DotMvn-Directory-Exists {
	[OutputType([bool])]
	Param (
		[Parameter(Mandatory, Position = 0)]
		[ValidateNotNullOrEmpty()]
		[string]$Path
	)
	$private:DotMvnFolderPath = Join-Path -Path $Path -ChildPath '.mvn'
	$private:DotMvnFolderExists = Test-Path $DotMvnFolderPath -PathType Container
	if ($DotMvnFolderExists) {
		Write-Debug -Message "$DotMvnFolderPath exists"
	}
 else {
		Write-Debug -Message "$DotMvnFolderPath does not exist"
	}
	return $DotMvnFolderExists
}

# get environment variables values
$private:MavenProjectBasedir = $env:MAVEN_BASEDIR
$private:SkipRc = $(Test-Path -Path 'env:MAVEN_SKIP_RC')
$private:BatchPause = $env:MAVEN_BATCH_PAUSE

# Execute a user defined script before this one
if (-not $SkipRc) {
	# check for pre script with .ps1 ending
	$private:MavenrcPath = Join-Path -Path $env:USERPROFILE -ChildPath 'mavenrc_pre.ps1'
	if (Test-Path $MavenrcPath) {
		Write-Verbose "Found mavenrc_pre.ps1 pre script: $MavenrcPath"
		& $MavenrcPath $RemainingParameters
		if ( !$? ) {
			Write-Warning -Message 'Error during pre script execution'
		}
	}
}

# trying to retrieve java.exe
if (Test-Path 'env:JAVA_HOME') {
	Write-Debug "Found JAVA_HOME environment variable: $env:JAVA_HOME"
	$private:JavaBinPath = Join-Path -Path $env:JAVA_HOME -ChildPath 'bin'
	$private:JavaExe = Join-Path -Path $JavaBinPath -ChildPath 'java.exe'
}
else {
	# looking for java.exe in PATH environment variable
	$private:JavaExe = (get-command java.exe).Path
}

if (-not (Test-Path $JavaExe)) {
	Write-Error -Message 'Unable to find java.exe'
	Write-Error -Message 'Please set the JAVA_HOME variable in your environment to match the location of your Java installation'
	Write-Error -Message 'or add the path to the java executable in the PATH environment variable'
	exit 1
}
Write-Verbose "Found java.exe: $JavaExe"

# if the project base dir is not defined at startup, it is initialized as the current location
if (!$MavenProjectBasedir) {
	$MavenProjectBasedir = Get-Location
}
Write-Debug -Message "Initialize the Maven project basedir as the current location: $MavenProjectBasedir"

# check if we are at the drive root or if the ".mvn" directory is in the current directory
# if not, update the project base dir to the parent directory of the current one
while (-not ($MavenProjectBasedir -eq '') -and -not (Test-DotMvn-Directory-Exists $MavenProjectBasedir)) {
	$MavenProjectBasedir = Split-Path $MavenProjectBasedir -Parent
	Write-Debug -Message "New Maven project basedir to check: $MavenProjectBasedir"
}

# Raise an error if we reach the drive root and no ".mvn" directory were found
if ($MavenProjectBasedir -eq '') {
	Write-Error -Message 'A .mvn directory is mandatory in the current directory or its parents directories'
	exit 1
}
Write-Verbose "Maven project basedir: $MavenProjectBasedir"

# get .mvn directory's files content if it exists
$private:JavaConfigMavenProps = @()
#$private:WrapperUrl = 'https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/@@project.version@@/maven-wrapper-@@project.version@@.jar'
$private:WrapperUrl = 'https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.1.1/maven-wrapper-3.1.1.jar'
$private:WrapperSha256Sum = $null
$private:MavenProjectDotMvnDir = Join-Path -Path $MavenProjectBasedir -ChildPath '.mvn'
$private:MavenWrapperPath = Join-Path -Path $MavenProjectDotMvnDir -ChildPath 'wrapper'
$private:MavenWrapperPropertiesFilePath = Join-Path -Path $MavenWrapperPath -ChildPath 'maven-wrapper.properties'

if (-not (Test-Path -Path $MavenWrapperPath) -or -not (Test-Path -Path $MavenWrapperPropertiesFilePath -PathType Leaf)) {
	Write-Error -Message 'The maven-wrapper.properties file is mandatory'
	exit 1
}

# get content of the jvm.config file in the .mvn directory, if it exists
$private:JvmConfigFilePath = Join-Path -Path $MavenProjectDotMvnDir -ChildPath 'jvm.config'
if (Test-Path -Path $JvmConfigFilePath -PathType Leaf) {
	Write-Verbose -Message "jvm.config file found: $JvmConfigFilePath"
	foreach ($private:Line in (Get-Content -Path $JvmConfigFilePath)) {
		$JavaConfigMavenProps += $Line
	}
}

# get content of the maven-wrapper.properties file in the .mvn directory
$private:DistributionUrl = $false
foreach ($Line in (Get-Content -Path $MavenWrapperPropertiesFilePath)) {
	if ($Line -match 'wrapperUrl=(.+)') {
		$WrapperUrl = $Matches[1].Trim()
	}
	if ($Line -match 'wrapperSha256Sum=(.+)') {
		$WrapperSha256Sum = $Matches[1].Trim()
	}
	if ($Line -match 'distributionUrl=(.+)') {
		$DistributionUrl = $true
	}
}

if (-not $DistributionUrl) {
	Write-Error -Message 'The distributionUrl property in the maven-wrapper.properties file is mandatory'
	exit 1
}

$private:MavenWrapperJarPath = Join-Path -Path $MavenWrapperPath -ChildPath 'maven-wrapper.jar'
$private:MavenWrapperLauncherClass = 'org.apache.maven.wrapper.MavenWrapperMain'

Write-Verbose -Message "Configuration properties"
Write-Verbose -Message "Java config maven properties: $JavaConfigMavenProps"
Write-Verbose -Message "Wrapper Url: $WrapperUrl"
Write-Verbose -Message "Wrapper directory path: $MavenWrapperPath"

# Automatically downloading the maven-wrapper.jar from Maven-central
# This allows using the maven wrapper in projects that prohibit checking in binary data.
if (Test-Path -Path $MavenWrapperJarPath -PathType Leaf) {
	Write-Verbose -Message "Found $MavenWrapperJarPath"
}
else {
	Write-Verbose -Message "Couldn't find $MavenWrapperJarPath, downloading it"
	Write-Verbose -Message "Downloading from: $WrapperUrl"

	# Override credential for basic authentication if environment variables are set
	if ((Test-Path -Path 'env:MVNW_USERNAME') -and (Test-Path -Path 'env:MVNW_PASSWORD')) {
		$private:SecurePasswordString = ConvertTo-SecureString -String $env:MVNW_PASSWORD -AsPlainText -Force
		$CredentialForBasicAuthentication = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $env:MVNW_USERNAME, $SecurePasswordString
	}

	try {
		$private:TempFileName = [System.IO.Path]::GetTempFileName()
		$private:ProxyUrl = ([System.Net.WebRequest]::GetSystemWebproxy()).GetProxy($WrapperUrl)
		$private:WebRequestArguments = @{
			Method  = "Get"
			Uri     = $WrapperUrl
			OutFile = $TempFileName
		}
		if ($ProxyUrl) {
			$WebRequestArguments["Proxy"] = $ProxyUrl
			$WebRequestArguments["ProxyUseDefaultCredentials"]
		} else {
			$WebRequestArguments["NoProxy"]
		}
		if ($CredentialForBasicAuthentication) {
			$WebRequestArguments["Credential"] = $CredentialForBasicAuthentication
		}

		# Get jar in a temporary file
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		Invoke-WebRequest @WebRequestArguments

		# Copy temporary file to destination, if it's still not there
		if (-not (Test-Path -Path $MavenWrapperJarPath -PathType Leaf)) {
			Move-Item -Path $TempFileName -Destination $MavenWrapperJarPath -Force
		}

		Write-Verbose -Message "Finished downloading: $MavenWrapperJarPath"
	}
	catch {
		Write-Error -Message "Error during the Maven Wrapper retrieval from URL: $WrapperUrl"
		Write-Error -Message $_
		exit 1
	}
}

# If specified, validate the SHA-256 sum of the Maven wrapper jar file
if ($WrapperSha256Sum) {
	if ((Get-FileHash -Path $MavenWrapperJarPath -Algorithm:SHA256).Hash.ToLower() -ne $WrapperSha256Sum.ToLower()) {
		Write-Error -Message 'Failed to validate Maven wrapper SHA-256, your Maven wrapper might be compromised.'
		Write-Error -Message "Investigate or delete $MavenWrapperJarPath to attempt a clean download."
		Write-Error -Message 'If you updated your Maven version, you need to update the specified wrapperSha256Sum property.'
		exit 1
	}
	Write-Verbose -Message 'Maven wrapper checksum ok'
}

# Launch maven command
& $JavaExe $JavaConfigMavenProps $env:MAVEN_OPTS $env:MAVEN_DEBUG_OPTS -classpath $MavenWrapperJarPath "-Dmaven.multiModuleProjectDirectory=$MavenProjectBasedir" $MavenWrapperLauncherClass $env:MAVEN_CONFIG $RemainingParameters

# Execute a user defined script after this one
if (-not $SkipRc) {
	# check for post script with .ps1 ending
	$private:MavenrcPath = Join-Path -Path $env:USERPROFILE -ChildPath 'mavenrc_post.ps1'
	if (Test-Path $MavenrcPath) {
		Write-Verbose "Found mavenrc_post.ps1 pre script: $MavenrcPath"
		& $MavenrcPath $RemainingParameters
		if ( !$? ) {
			Write-Warning -Message 'Error during post script execution'
		}
	}
}

# pause the script if BatchPause is set to 'on'
if ($BatchPause -and $BatchPause.ToLower() -eq 'on') {
	$private:null = Read-Host -Prompt "Press the Enter key to continue..."
}