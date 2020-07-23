<#
.Synopsis
Starts a webserver in Powershell serving a website where you can order Burgers.
.Description
Credits: This is based on the Powershell Web Server of Markus Scholtes: https://github.com/MScholtes/SysAdminsFriends
Starts a webserver in Powershell. This is a very dirty approach and just an attempt to entertain my coworkers.
Call of the root page (e.g. http://localhost:8080/) returns a website to order Burgers.
Call of /log returns the webserver logs.
/exit stops the webserver.
Any other call delivers the static content that fits to the path provided. If the static path is a directory,
a file index.htm, index.html, default.htm or default.html in this directory is delivered if present.

You may have to configure a firewall exception to allow access to the chosen port, e.g. with:
	netsh advfirewall firewall add rule name="Powershell Webserver" dir=in action=allow protocol=TCP localport=8080

After stopping the webserver you should remove the rule, e.g.:
	netsh advfirewall firewall delete rule name="Powershell Webserver"
.Parameter BINDING
Binding of the webserver
.Parameter BASEDIR
Base directory for static content (default: current directory)
.Parameter BannerImg
Url to an optional banner image next to the table with the placed orders
.Parameter BannerUrl
Url for an optional link on the banner image
.Inputs
None
.Outputs
Log Messages
.Example
Start-Webserver.ps1

Starts webserver with binding to http://localhost:8080/
.Example
Start-Webserver.ps1 "http://+:8080/"

Starts webserver with binding to all IP addresses of the system.
Administrative rights are necessary.
.Notes
Version: See $Version below
Author: Florian Diwald
#>
Param([STRING]$Binding = 'http://localhost:8080/', [STRING]$BaseDir = "", [string]$BannerImg = "", [string]$BannerUrl = "")

Add-Type -AssemblyName System.Web

$Product = "PSBurgers"
$Version = "1.2"
# No adminstrative permissions are required for a binding to "localhost"
# $Binding = 'http://localhost:8080/'
# Adminstrative permissions are required for a binding to network names or addresses.
# + takes all requests to the port regardless of name or ip, * only requests that no other listener answers:
# $Binding = 'http://+:8080/'

function Initialize-Webserver {
    # Initial one time tasks
    # Constants
    Set-Variable -Name ATTRIBUTE_NAME -Value "Name" -Option Constant -Scope Script
    Set-Variable -Name ATTRIBUTE_COMMENT -Value "Comment" -Option Constant -Scope Script
    Set-Variable -Name ATTRIBUTE_GUID -Value "Guid" -Option Constant -Scope Script

    if ($BaseDir -eq "")
    {	# current filesystem path as base path for static content
        $Script:BaseDir = (Get-Location -PSProvider "FileSystem").ToString()
    }
    # convert to absolute path
    $Script:BaseDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BaseDir)
    
    Set-Variable -Name OrdersFile -Value "$BaseDir\Orders.xml" -Option Constant -Scope Script
    Set-Variable -Name StyleFile -Value "$BaseDir\style.css" -Option Constant -Scope Script

    # A GUID which the user needs to access the administration page
    $Script:AdminGuid = New-Guid
    "Admin-Access: $Binding$Script:AdminGuid".Replace("+", $env:computername).Replace("*", $env:computername) | Write-Log;
    
    $HtmlHead = @"
    <head>
    <meta charset="UTF-8">
    <link rel="stylesheet" href="/style.css">
    </head>
"@
    
    # navigation header line
    $MenuLinks = @"
    <p>
    <a href='/'>Burger bestellen</a>
    <a href='/log'>Web logs</a>
    <a href='/exit'>Stop webserver</a>
    <a href='/reloadOrders'>Reload orders</a>
    </p>
"@
    
    if($BannerImg -ne "") {
        $BannerHtml = "<img src=""$BannerImg"">"
        if ($BannerUrl -ne "") {
            $BannerHtml = "<a href=""$BannerUrl"">$BannerHtml</a>"
        }
        $BannerHtml = "<div class=""spacer20""></div><div id=""banner"">$BannerHtml</div>"
    }
    $DefaultPage = @"
    <!doctype html><html>$HtmlHead
    <body><h1>Burger bestellen</h1>
    !ORDERTABLE
    $BannerHtml
    </body></html>
"@

    # HTML answer templates for specific calls
    $Script:HtmlResponseContent = @{
        'GET /' = $DefaultPage
        'POST /' = $DefaultPage
        'GET /exit' = "<!doctype html><html>$HtmlHead<body>Stopped powershell webserver</body></html>"
        "GET /$Script:AdminGuid" = "<!doctype html><html>$HtmlHead<body>$MenuLinks<br>!ORDERTABLE<br>Log of powershell webserver:<br><pre>!WEBLOG</pre></body></html>"
        'GET /style.css' = "!STYLECSS"
    }

    Read-Orders
}

function Read-Orders {
    # Read already placed Orders from a file if exists, otherwise create the $Orders object from scratch.
    if (Test-Path $OrdersFile -PathType Leaf) {
        [XML]$Script:Orders = Get-Content $OrdersFile
    } else {
        [XML]$Script:Orders = New-Object -TypeName System.Xml.XmlDocument
        [System.Xml.XmlNode]$RootNode = $Orders.CreateElement("Orders")
        $Orders.AppendChild($RootNode) | Out-Null
    }
}

function Add-Order ([string]$Name, [string]$Comment) {
    # Adds a new Order into the $Order object.
    $NewOrder = $Orders.CreateElement("Order")
    $NewOrder.SetAttribute($ATTRIBUTE_GUID, (New-Guid))
    $NewOrder.SetAttribute($ATTRIBUTE_NAME, $Name)
    $NewOrder.SetAttribute($ATTRIBUTE_COMMENT, $Comment)
    $Orders.FirstChild.AppendChild($NewOrder) | Out-Null
    $Orders.Save($OrdersFile) | Write-Log
}

function Get-OrderTable {
    foreach($Order in $Orders.SelectNodes("/Orders/Order")) {
        $Comment = $Order.GetAttribute($ATTRIBUTE_COMMENT)
        if ($null -eq $Comment) {
            $Comment = ""
        }
        $PreviousOrders += "<tr><td>$($Order.GetAttribute($ATTRIBUTE_NAME))</td><td>$($Comment)</td></tr>"
    }

    @"
    <div class="tablewrapper">
        <form action="/" method="post">
            <table><thead><tr><th>Name</th><th>Bemerkung</th></tr></thead>
                <tbody>
                    $PreviousOrders
                    <tr>
                        <td>
                            <input type="text" name="name" placeholder="Dein Name">
                        </td>
                        <td>
                            <input type="text" name="comment" placeholder="Bemerkung">
                            <input type="submit" value="Bestellen">
                        </td>
                    </tr>
                </tbody>
            </table>
        </form>
    </div>
"@
}
function Start-Listening {
    # Starting the powershell webserver
    "Starting powershell webserver..." | Write-Log
    $Script:Listener = New-Object System.Net.HttpListener
    $Listener.Prefixes.Add($Binding) | Write-Log
    try
    {
        $Listener.Start() | Write-Log
        "Powershell webserver started on $Binding." | Write-Log
    }
    catch{
        $Error | Write-Log
        $Error.Clear() | Out-Null
    }

    try
    {
        while ($Listener.IsListening)
        {
            Pop-Request
            if (-not $ContinueListening) {
                break
            }
        }
    }
    finally
    {
        # Stop powershell webserver
        $Listener.Stop() | Out-Null
        $Listener.Close() | Out-Null
        "Powershell webserver stopped." | Write-Log
    }
}
function Save-Order([string]$RequestData) {
    # Parse the data from the HTTP-Request into the $Orders-XML document.
    $Name = ""
    foreach($KeyValuePair in $RequestData -split "&") {
        $KeyAndValue = $KeyValuePair -split "="
        switch ($KeyAndValue[0]) {
            "name" {
                $Name = [System.Web.HttpUtility]::UrlDecode($KeyAndValue[1])
                break
            }
            "comment" {
                $Comment = [System.Web.HttpUtility]::UrlDecode($KeyAndValue[1])
                break
            }
        }
    }
    if($Name -eq "") {
        "Request ignored: No name given" | Write-Log
    } else {
        Add-Order $Name $Comment
    }
}
function Pop-Request {
    # Get a request from the stack and process it
    $Context = $Listener.GetContext()
    [System.Net.HttpListenerRequest]$Request = $Context.Request
    $Response = $Context.Response
    $Script:ContinueListening = $true

    # log access
    "$($Request.RemoteEndPoint.Address.ToString()) $($Request.httpMethod) $($Request.Url.PathAndQuery)" | Write-Log

    # is there a fixed coding for the request?
    $Received = '{0} {1}' -f $Request.httpMethod, $Request.Url.LocalPath
    $HtmlResponse = $HtmlResponseContent[$Received]

    # check for known commands
    switch ($Received)
    {
        "POST /"
        {
            if ($Request.HasEntityBody){
                # read all the posted parameters into $Data
                $Reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
                $Data = $Reader.ReadToEnd()
                $Reader.Close()
                $Request.InputStream.Close()

                $Data | Write-Log
                Save-Order $Data
            }
            break
        }

        "GET /exit"
        {
            $Script:ContinueListening = $false
            break
        }
    }

    # replace the dynamic parts
    $HtmlResponse = $HtmlResponse -replace '!WEBLOG', $WebLog
    $HtmlResponse = $HtmlResponse -replace '!ORDERTABLE', (Get-OrderTable)
    $HtmlResponse = $HtmlResponse -replace '!STYLECSS', (Get-Content $StyleFile)

    # return HTML answer to caller
    $Buffer = [Text.Encoding]::UTF8.GetBytes($HtmlResponse)
    $Response.ContentLength64 = $Buffer.Length
    $Response.AddHeader("Last-Modified", [DATETIME]::Now.ToString('r'))
    $Response.AddHeader("Server", "$Product $Version")
    $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)

    # and finish answer to client
    $Response.Close()
}

function Write-Log {
    process {
        $Message = (Get-Date -Format s) + ": $_"
        $Script:WebLog += $Message + "`n"
        $Message
    }
}

Initialize-Webserver
Start-Listening