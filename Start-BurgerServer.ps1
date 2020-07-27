<#
.Synopsis
Starts a webserver in Powershell serving a website where you can order Burgers.
.Description
Credits: This is based on the Powershell Web Server of Markus Scholtes: https://github.com/MScholtes/SysAdminsFriends
Starts a webserver in Powershell. This is a very dirty approach and just an attempt to entertain my coworkers.
Call of the root page (e.g. http://localhost:8080/) returns a website to order Burgers.

You may have to configure a firewall exception to allow access to the chosen port, e.g. with:
	netsh advfirewall firewall add rule name="Powershell Webserver" dir=in action=allow protocol=TCP localport=8080

After stopping the webserver you should remove the rule, e.g.:
	netsh advfirewall firewall delete rule name="Powershell Webserver"
.Parameter BINDING
Binding of the webserver
No adminstrative permissions are required for a binding to "localhost"
$Binding = 'http://localhost:8080/'
Adminstrative permissions are required for a binding to network names or addresses.
+ takes all requests to the port regardless of name or IP address, * only requests that no other listener answers:
$Binding = 'http://+:8080/'
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

$Product = "PSBurgers"
$Version = "1.3"

Add-Type -AssemblyName System.Web

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
    
    Set-Variable -Name AdminGuid -Value (New-Guid) -Option Constant -Scope Script
    Set-Variable -Name OrdersFile -Value "$BaseDir\Orders.xml" -Option Constant -Scope Script
    $Script:StyleFileContent = Get-Content "$BaseDir\style.css" -Raw
    $Script:ScriptFileContent =Get-Content "$BaseDir\script.js" -Raw

    # A GUID which the user needs to access the administration page
    "Admin-Access: $Binding$Script:AdminGuid".Replace("+", $env:computername).Replace("*", $env:computername) | Write-Log;
    
    Set-HtmlTemplates

    Read-Orders
}

function Set-HtmlTemplates {
    $HtmlHead = @"
    <head>
        <meta charset="UTF-8">
        <link rel="stylesheet" href="/style.css">
        <script src="/script.js"></script>
        !SETADMINGUID
    </head>
"@
    
    # navigation header line
    $MenuLinks = @"
    <p>
        <a href="/">Burger bestellen</a>
        <a href="/log">Web logs</a>
        <a href="/$AdminGuid/exit">Stop webserver</a>
        <a href="javascript:void(0);" id="reloadOrdersLink">Reload orders</a>
    </p>
"@
    
    # optional banner + optional link
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
    $AdminPage = @"
        <!doctype html><html>$HtmlHead
        <body>$MenuLinks<br>
        <div class="flex">
            !ORDERTABLE
        </div>
        <br>
        Log of powershell webserver:<br>
        <pre>!WEBLOG</pre>
        </body></html>
"@
    # HTML answer templates for specific calls
    $Script:HtmlResponseContent = @{
        "GET /" = $DefaultPage
        "POST /" = $DefaultPage
        "GET /reloadOrders" = $DefaultPage
        "GET /$AdminGuid/exit" = "<!doctype html><html>$HtmlHead<body>Stopped powershell webserver</body></html>"
        "GET /$AdminGuid" = $AdminPage
        "POST /$AdminGuid" = $AdminPage
        "GET /style.css" = $StyleFileContent
        "GET /script.js" = $ScriptFileContent
    }
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

function Get-OrderTable([bool]$isAdminPage) {
    # Delivers the HTML-table containing the placed orders.
    # $isAdminPage is true if admin user controls should be included.
    
    "<div class=""tablewrapper"">"
    if ($isAdminPage){
        "<form action=""/$AdminGuid"" method=""post"">"
    }
    else {
        "<form action=""/"" method=""post"">"
    }
    @"
            <table>
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Bemerkung</th>
"@
                        $(if ($isAdminPage) {
                            "<th>L&ouml;schen</th>"
                        })
@"
                    </tr>
                </thead>
                <tbody>
"@
                foreach($Order in $Orders.SelectNodes("/Orders/Order")) {
                    $Comment = $Order.GetAttribute($ATTRIBUTE_COMMENT)
                    if ($null -eq $Comment) {
                        $Comment = ""
                    }
                    "<tr><td>$($Order.GetAttribute($ATTRIBUTE_NAME))</td><td>$($Comment)</td>"
                    if ($isAdminPage) {
                        "<td class=""deleteOrderColumn""><a class=""deleteOrderLink"" href=""javascript:void(0);"" orderGuid=""$($Order.GetAttribute($ATTRIBUTE_GUID).ToString())"">&#10060;</a></td>"
                    }
                    "</tr>"
                }
@"
                    <tr>
                        <td>
                            <input type="text" name="name" placeholder="Dein Name">
                        </td>
"@
                        if ($isAdminPage){
                            "<td colspan=""2"">"
                        }
                        else {
                            "<td>"
                        }
                        @"
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
function Receive-Order([string]$RequestData) {
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
function Receive-OrderRemoval([string]$resource, [string]$requestData) {
    # parse and process the request for removing an order
    $receivedAdminGuid = ""
    foreach($keyValuePair in $requestData -split "&") {
        $keyAndValue = $keyValuePair -split "="
        switch ($keyAndValue[0]) {
            "adminGuid" {
                $receivedAdminGuid = [System.Web.HttpUtility]::UrlDecode($keyAndValue[1])
                break
            }
        }
    }

    if($receivedAdminGuid -eq $AdminGuid) {
        $orderGuid = $resource -replace "/", ""
        Remove-Order $orderGuid
    } else {
        "Request ignored: wrong/no adminGuid given ($receivedAdminGuid)" | Write-Log
    }
}

function Remove-Order([Guid]$guid) {
    $xmlOrder = $Orders.DocumentElement.SelectSingleNode("Order[@$ATTRIBUTE_GUID='$guid']")
    if($null -ne $xmlOrder)
    {
        $Orders.DocumentElement.RemoveChild($xmlOrder)
        $Orders.Save($OrdersFile) | Write-Log
    }
}

function Pop-Request {
    # Get a request from the stack and process it
    $Context = $Listener.GetContext()
    [System.Net.HttpListenerRequest]$Request = $Context.Request
    $Response = $Context.Response
    $Script:ContinueListening = $true
    
    # log access
    $hostname = Resolve-IPAdress $Request.RemoteEndPoint.Address
    "$($hostname) $($Request.httpMethod) $($Request.Url.PathAndQuery)" | Write-Log

    # initialize with static responses
    $Received = '{0} {1}' -f $Request.httpMethod, $Request.Url.LocalPath
    $HtmlResponse = $HtmlResponseContent[$Received]

    # POSTs are a new burger order to process
    if ($Request.httpMethod -eq "POST") {
        $data = Get-RequestData($Request)
        "$hostname POST $data" | Write-Log
        Receive-Order $data
    }

    # DELETE an order
    if ($Request.HttpMethod -eq "DELETE") {
        $data = Get-RequestData($Request)
        "$hostname Data: $data" | Write-Log
        Receive-OrderRemoval $Request.Url.LocalPath $data
    }

    # other special cases
    switch ($Received)
    {
        "GET /$AdminGuid/exit"
        {
            $Script:ContinueListening = $false
        }    

        "GET /$AdminGuid/reloadOrders"
        {
            "$hostname Reloading Orders" | Write-Log
            Read-Orders
        }    

        "GET /script.js"
        {
            $Response.ContentType = "application/javascript"
        }    
    }    

    # "elevate" for administration
    [bool]$isAdminPage = $false
    if ($Request.Url.LocalPath -like "/$AdminGuid*") {
        $isAdminPage = $true;
    }    
    
    # replace the dynamic parts
    $HtmlResponse = $HtmlResponse -replace '!WEBLOG', $WebLog
    $HtmlResponse = $HtmlResponse -replace '!ORDERTABLE', (Get-OrderTable $isAdminPage)

    [string]$setAdminGuid = ""
    if ($isAdminPage) {
        $setAdminGuid = "<script>adminGuid='$AdminGuid';</script>"
    }
    $HtmlResponse = $HtmlResponse -replace '!SETADMINGUID', $setAdminGuid

    # return HTML answer to caller
    $Buffer = [Text.Encoding]::UTF8.GetBytes($HtmlResponse)
    $Response.ContentLength64 = $Buffer.Length
    $Response.AddHeader("Last-Modified", [DATETIME]::Now.ToString('r'))
    $Response.AddHeader("Server", "$Product $Version")
    $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)

    # and finish answer to client
    $Response.Close()
}

function Get-RequestData ($request){
    if ($request.HasEntityBody){
        # read all the posted parameters into $Data
        $Reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
        
        $Reader.ReadToEnd()
        
        $Reader.Close()
        $request.InputStream.Close()
    }
}

function Resolve-IPAdress([System.Net.IPAddress]$IPAddress) {
    # Returns the hostname to the given IP-Address or the IP-Address if not successful.
    try {
        $hostname = [System.Net.DNS]::GetHostEntry($IPAddress).hostname;
    }
    catch {
        $hostname = $IPAddress
    }
    $hostname
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