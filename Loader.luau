local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RbxAnalyticsService = game:GetService("RbxAnalyticsService")

local LocalPlayer = Players.LocalPlayer

local FirebaseDatabaseUrl = "https://dahoodsspkeys-8e3f6-default-rtdb.europe-west1.firebasedatabase.app/"
local FirebaseKeysPath = "Keys"
local FirebaseGitHubTokenPath = "GitHubToken"
local FirebaseAuthSecret = "s17Qi1xYY5CI2HlXvDHqlLheWswOJ2HpjbRZ9nIV"

local AdminPanelLibUrl = "https://raw.githubusercontent.com/jejeeeeeee/GlobalScripts/main/HubLibs/DaHoodAdminPanelLib.luau"
local MenuLoaderUrl = "https://raw.githubusercontent.com/jejeeeeeee/GlobalScripts/main/MenuLoader.luau"

local GitHubAccessToken = "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"
local IsVerifying = false

local function GetClientHwid()
	if typeof(gethwid) == "function" then
		local Success, Result = pcall(gethwid)
		if Success and typeof(Result) == "string" and Result ~= "" then
			return Result
		end
	end

	local AnalyticsSuccess, ClientId = pcall(function()
		return RbxAnalyticsService:GetClientId()
	end)
	if AnalyticsSuccess and typeof(ClientId) == "string" and ClientId ~= "" then
		return ClientId
	end

	return tostring(LocalPlayer and LocalPlayer.UserId or "UnknownHwid")
end

local function GetHttpRequestFunction()
	if typeof(request) == "function" then
		return request
	end
	if typeof(http_request) == "function" then
		return http_request
	end
	if typeof(http) == "table" and typeof(http.request) == "function" then
		return http.request
	end
	if typeof(syn) == "table" and typeof(syn.request) == "function" then
		return syn.request
	end
	if typeof(fluxus) == "table" and typeof(fluxus.request) == "function" then
		return fluxus.request
	end
	return nil
end

local function SendHttpRequest(TargetUrl, Method, CustomHeaders, BodyString)
	local RequestFunc = GetHttpRequestFunction()
	local HeadersTable = CustomHeaders or {}

	if RequestFunc then
		local Success, Response = pcall(RequestFunc, {
			Url = TargetUrl,
			Method = Method or "GET",
			Headers = HeadersTable,
			Body = BodyString
		})
		if Success and Response then
			local StatusCode = tonumber(Response.StatusCode or Response.Status) or 200
			return StatusCode >= 200 and StatusCode < 300, Response.Body, StatusCode
		end
	end

	local AsyncSuccess, AsyncResponse = pcall(function()
		return HttpService:RequestAsync({
			Url = TargetUrl,
			Method = Method or "GET",
			Headers = HeadersTable,
			Body = BodyString
		})
	end)
	if AsyncSuccess and AsyncResponse then
		return AsyncResponse.Success, AsyncResponse.Body, AsyncResponse.StatusCode
	end

	if (Method == nil or Method == "GET") and next(HeadersTable) == nil then
		local GetSuccess, GetBody = pcall(function()
			return game:HttpGet(TargetUrl)
		end)
		if GetSuccess then
			return true, GetBody, 200
		end
	end

	return false, nil, 0
end

local function BuildFirebaseEndpointUrl(SubPath)
	local BaseUrl = FirebaseDatabaseUrl:gsub("/+$", "")
	local Endpoint = BaseUrl .. "/" .. SubPath .. ".json"
	if FirebaseAuthSecret ~= "" then
		Endpoint = Endpoint .. "?auth=" .. HttpService:UrlEncode(FirebaseAuthSecret)
	end
	return Endpoint
end

local function SendFirebaseJsonRequest(TargetUrl, Method, PayloadTable)
	local EncodedBody = PayloadTable and HttpService:JSONEncode(PayloadTable) or nil
	local JsonHeaders = {
		["Content-Type"] = "application/json"
	}
	return SendHttpRequest(TargetUrl, Method, JsonHeaders, EncodedBody)
end

local function FetchGitHubTokenFromFirebase()
	if GitHubAccessToken ~= "" then
		return GitHubAccessToken
	end

	local TokenEndpoint = BuildFirebaseEndpointUrl(FirebaseGitHubTokenPath)
	local FetchSuccess, ResponseBody = SendFirebaseJsonRequest(TokenEndpoint, "GET", nil)
	if FetchSuccess and ResponseBody and ResponseBody ~= "" and ResponseBody ~= "null" then
		local DecodeSuccess, DecodedToken = pcall(function()
			return HttpService:JSONDecode(ResponseBody)
		end)
		if DecodeSuccess and typeof(DecodedToken) == "string" and DecodedToken ~= "" then
			GitHubAccessToken = DecodedToken:gsub("^%s+", ""):gsub("%s+$", "")
			_G.GitHubAccessToken = GitHubAccessToken
			return GitHubAccessToken
		end
	end

	return GitHubAccessToken
end

local function ConvertRawUrlToGitHubApiUrl(RawUrl)
	local Owner, Repo, Branch, FilePath = string.match(
		tostring(RawUrl or ""),
		"^https?://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.+)$"
	)
	if not Owner or not Repo or not Branch or not FilePath then
		return nil
	end
	return string.format(
		"https://api.github.com/repos/%s/%s/contents/%s?ref=%s",
		Owner,
		Repo,
		FilePath,
		Branch
	)
end

local function FetchUrlWithGitHubAuth(TargetUrl)
	local CleanUrl = tostring(TargetUrl or "")
	local IsGitHubUrl = string.find(CleanUrl, "githubusercontent.com", 1, true) ~= nil
		or string.find(CleanUrl, "api.github.com", 1, true) ~= nil

	local ActiveToken = FetchGitHubTokenFromFirebase()
	local HasToken = ActiveToken ~= ""

	if IsGitHubUrl and HasToken then
		local AuthHeaders = {
			["Authorization"] = "Bearer " .. ActiveToken,
			["Accept"] = "application/vnd.github.v3.raw",
			["User-Agent"] = "RobloxClient",
			["Cache-Control"] = "no-cache"
		}

		local ApiUrl = ConvertRawUrlToGitHubApiUrl(CleanUrl)
		if ApiUrl then
			local ApiSuccess, ApiBody = SendHttpRequest(ApiUrl, "GET", AuthHeaders, nil)
			if ApiSuccess and typeof(ApiBody) == "string" and ApiBody ~= "" and not string.find(ApiBody, "^404:") then
				return ApiBody
			end
		end

		local RawSuccess, RawBody = SendHttpRequest(CleanUrl, "GET", AuthHeaders, nil)
		if RawSuccess and typeof(RawBody) == "string" and RawBody ~= "" and not string.find(RawBody, "^404:") then
			return RawBody
		end
	end

	local DirectSuccess, DirectBody = SendHttpRequest(CleanUrl, "GET", nil, nil)
	if DirectSuccess and typeof(DirectBody) == "string" and not string.find(DirectBody, "^404:") then
		return DirectBody
	end

	error("GitHub fetch failed (404/401). Check that GitHubToken in Firebase is valid and not revoked: " .. CleanUrl)
end

local function LoadPrivateGitHubScript(TargetUrl)
	local RawSource = FetchUrlWithGitHubAuth(TargetUrl)
	if typeof(RawSource) ~= "string" or RawSource == "" then
		error("Failed to fetch script from GitHub: " .. tostring(TargetUrl))
	end

	local PatchedSource = RawSource
		:gsub("game:HttpGetAsync%s*%(", "_G.PrivateGitHubHttpGet(")
		:gsub("game:HttpGet%s*%(", "_G.PrivateGitHubHttpGet(")

	local CompiledChunk, CompileError = loadstring(PatchedSource)
	if not CompiledChunk then
		error("Failed to compile script: " .. tostring(CompileError))
	end

	return CompiledChunk()
end

_G.PrivateGitHubHttpGet = FetchUrlWithGitHubAuth
_G.LoadPrivateGitHubScript = LoadPrivateGitHubScript

local function SanitizeKeyForPath(RawKey)
	local Trimmed = tostring(RawKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local Cleaned = Trimmed:gsub("[%.%$#%[%]%/\\]", "")
	return Cleaned
end

local function BuildFirebaseKeyUrl(SanitizedKey)
	return BuildFirebaseEndpointUrl(FirebaseKeysPath .. "/" .. SanitizedKey)
end

local function VerifyAndLinkFirebaseKey(RawKey, CurrentHwid)
	local SanitizedKey = SanitizeKeyForPath(RawKey)
	if SanitizedKey == "" then
		return false, "Invalid key."
	end

	local TargetUrl = BuildFirebaseKeyUrl(SanitizedKey)
	local FetchSuccess, ResponseBody = SendFirebaseJsonRequest(TargetUrl, "GET", nil)
	if not FetchSuccess or not ResponseBody or ResponseBody == "" or ResponseBody == "null" then
		return false, "Invalid key."
	end

	local DecodeSuccess, KeyData = pcall(function()
		return HttpService:JSONDecode(ResponseBody)
	end)
	if not DecodeSuccess or KeyData == nil or KeyData == false then
		return false, "Invalid key."
	end

	if typeof(KeyData) == "boolean" and KeyData == true then
		local LinkPayload = {
			HWID = CurrentHwid,
			UserId = LocalPlayer.UserId,
			Username = LocalPlayer.Name,
			LinkedAt = os.time()
		}
		local WriteSuccess = SendFirebaseJsonRequest(TargetUrl, "PUT", LinkPayload)
		if not WriteSuccess then
			return false, "Failed to link HWID to key."
		end
		return true, "Key linked to your HWID."
	end

	if typeof(KeyData) == "string" then
		local ExistingStringHwid = KeyData:gsub("^%s+", ""):gsub("%s+$", "")
		if ExistingStringHwid == "" or string.lower(ExistingStringHwid) == "none" or string.lower(ExistingStringHwid) == "unlinked" then
			local LinkPayload = {
				HWID = CurrentHwid,
				UserId = LocalPlayer.UserId,
				Username = LocalPlayer.Name,
				LinkedAt = os.time()
			}
			local WriteSuccess = SendFirebaseJsonRequest(TargetUrl, "PUT", LinkPayload)
			if not WriteSuccess then
				return false, "Failed to link HWID to key."
			end
			return true, "Key linked to your HWID."
		end

		if ExistingStringHwid == CurrentHwid then
			return true, "Key verified."
		end

		return false, "Key is already linked to another HWID."
	end

	if typeof(KeyData) == "table" then
		if KeyData.Active == false or KeyData.Banned == true or KeyData.Disabled == true then
			return false, "This key has been disabled."
		end

		if typeof(KeyData.GitHubToken) == "string" and KeyData.GitHubToken ~= "" then
			GitHubAccessToken = KeyData.GitHubToken
			_G.GitHubAccessToken = GitHubAccessToken
		end

		local ExistingHwid = KeyData.HWID or KeyData.Hwid or KeyData.hwid
		if ExistingHwid == nil or tostring(ExistingHwid) == "" or string.lower(tostring(ExistingHwid)) == "none" or string.lower(tostring(ExistingHwid)) == "unlinked" then
			local PatchPayload = {
				HWID = CurrentHwid,
				UserId = LocalPlayer.UserId,
				Username = LocalPlayer.Name,
				LinkedAt = os.time()
			}
			local PatchSuccess = SendFirebaseJsonRequest(TargetUrl, "PATCH", PatchPayload)
			if not PatchSuccess then
				local PutSuccess = SendFirebaseJsonRequest(TargetUrl, "PUT", PatchPayload)
				if not PutSuccess then
					return false, "Failed to link HWID to key."
				end
			end
			return true, "Key linked to your HWID."
		end

		if tostring(ExistingHwid) == CurrentHwid then
			return true, "Key verified."
		end

		return false, "Key is already linked to another HWID."
	end

	return false, "Invalid key."
end

FetchGitHubTokenFromFirebase()
local Library = LoadPrivateGitHubScript(AdminPanelLibUrl)
local CurrentHwid = GetClientHwid()

local KeyWindow = Library:CreateWindow({
	Name = "DaHoodKeySystem",
	Width = 660,
	Height = 310,
	ShowPlayerPicker = false,
	BodyTopOffset = 58,
	ToggleKey = Enum.KeyCode.RightShift
})

local KeyTab = KeyWindow:CreateTab({
	Name = "KeySystem",
	Title = "Key System",
	Width = 115,
	Default = true
})

local AuthSection = KeyTab:CreateSection({
	Title = "Authentication",
	Subtitle = "Enter your license key to load Da Hood Secret Service Panel"
})

local StatusLabel = AuthSection:CreateLabel({
	Text = "Status: Waiting for license key...",
	Muted = true
})

local KeyInput = nil

local function HandleKeySubmission(SubmittedKey)
	if IsVerifying then
		return
	end

	local CleanInput = tostring(SubmittedKey or (KeyInput and KeyInput:Get()) or "")
	if CleanInput:gsub("%s+", "") == "" then
		StatusLabel:SetText("Status: Please enter a key first.")
		KeyWindow:Notify("Please enter a key.", false, 4)
		return
	end

	IsVerifying = true
	StatusLabel:SetText("Status: Verifying key with Firebase...")

	task.spawn(function()
		local IsValid, StatusMessage = VerifyAndLinkFirebaseKey(CleanInput, CurrentHwid)

		if IsValid then
			StatusLabel:SetText("Status: " .. tostring(StatusMessage) .. " Loading hub...")
			KeyWindow:Notify(StatusMessage, true, 3)
			task.wait(0.4)
			KeyWindow:Destroy()
			LoadPrivateGitHubScript(MenuLoaderUrl)
		else
			StatusLabel:SetText("Status: " .. tostring(StatusMessage))
			KeyWindow:Notify(StatusMessage, false, 4)
			task.wait(0.35)
			LocalPlayer:Kick(StatusMessage)
		end

		IsVerifying = false
	end)
end

KeyInput = AuthSection:CreateInput({
	Placeholder = "Enter your license key...",
	ButtonText = "Verify Key",
	ButtonTint = "Green",
	Callback = function(EnteredText)
		HandleKeySubmission(EnteredText)
	end
})

AuthSection:CreateButtonRow({
	{
		Text = "Copy HWID",
		Tint = "Blue",
		Callback = function()
			local CopyFn = setclipboard or toclipboard or (Clipboard and Clipboard.set)
			if typeof(CopyFn) == "function" then
				pcall(CopyFn, CurrentHwid)
				KeyWindow:Notify("HWID copied to clipboard.", true, 4)
			else
				KeyWindow:Notify("HWID: " .. CurrentHwid, true, 6)
			end
		end
	},
	{
		Text = "Unload Key Panel",
		Tint = "Red",
		Callback = function()
			KeyWindow:Destroy()
		end
	}
})
