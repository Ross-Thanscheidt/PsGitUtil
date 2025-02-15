<# 
	GitUtil is a collection of powershell utilities to be used in combination with git.
	
	Author: Anthony James
	Created: 12/6/2012
#>

if(Get-Module PsGitUtil) { return }

function require-CleanWorking([switch]$quiet, [switch]$return){
	git diff --quiet
	if($lastexitcode -ne 0 -and $quiet -ne $true){
		throw 'The working directory is not clean. Please stash or commit your changes before continuing.';
	}
	elseif($lastexitcode -ne 0 -and $return -eq $true){
		return $false;
	}
	elseif($return -eq $true){
		return $true;
	}
	elseif($lastexitcode -ne 0){
		$global:LASTEXITCODE = 1;
	}
	else{
		$global:LASTEXITCODE = 0;
	}
}

function check-BranchExists
{
	param(
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)]
		[string]
		$branchName,
		
		[Parameter(Mandatory=$false)]
		[switch]
		$localOnly,
		
		[Parameter(Mandatory=$false)]
		[switch]
		$remoteOnly
	)
	begin{
		if($remoteOnly -eq $true `
			-and $localOnly -eq $true){
			throw 'You cannot define both localOnly and remoteOnly flags.';
		}
	}
	process{
		$refs = git show-ref
		$localExists = (git show-ref | 
						%{ $_.Split(' ')[1] } | 
						Where-Object{ $_ -imatch '/heads/' -and ((Split-Path $_ -Leaf) -ieq $branchName) }).Length -gt 0;
						#The below will match branches that contain part of the branch name as well
#						Where-Object{ $_ -imatch '/heads/' -and $_ -imatch $branchName }).Length -gt 0;
		$remoteExists = (git show-ref |
						%{ $_.Split(' ')[1] } |
						Where-Object{ $_ -imatch '/remotes/' -and ((Split-Path $_ -Leaf) -ieq $branchName) }).Length -gt 0;
#						Where-Object{ $_ -imatch '/remotes/' -and $_ -imatch $branchName }).Length -gt 0;
						
		if($remoteOnly -eq $true){
			return $remoteExists;
		}
		elseif($localOnly -eq $true){
			return $localExists;
		}
		else{
			return $remoteExists -or $localExists;
		}
	}
}

function check-BranchMerged([string]$branchName){
	$mergedIntoMeasure = git branch --contains $branchName | Where-Object{ $_.Replace('*', '').Trim() -ine $branchName } | Measure-Object
	if($mergedIntoMeasure.Count -gt 0){
		return $true;
	}
	else{
		return $false;
	}
}

<#
	.SYNOPSIS
	Loops through each deleted file and stages it for commit.
	
	.DESCRIPTION
	This funciton uses git ls-files --deleted to identify all deleted files in the repository.
	The result is piped into a loop which stages them as removed.
#>
function git-StageDeleted(){
	git ls-files --deleted | %{ git rm $_ }
	
	##This method works too, but I like the above better because it's cleaner.
	##if((git ls-files --deleted | measure).Count -gt 0){
	##	git rm $(git ls-files --deleted)
	##}
}
Set-Alias gsd git-StageDeleted

<#
	.SYNOPSIS
		Performs necessary staging actions, and then asks if you're ready for commit.
	
	.DESCRIPTION
		This function performs all the necessary staging actions before a commit.
		You can also pass the push switch parameter to call git push once the commit is complete.
	
	.PARAMETER	stage
		Boolean value indicating that you would like to stage everything in the index.
		If you do not provide this parameter, git status will be called, and you will be asked if you want to stage.
		Stages can only be committed if you stage.
	
	.PARAMETER	commit
		Boolean value indicating that you would like to commit your staged changes.
		If you do not provide this parameter, you will be asked if you would like to commit.
	
	.PARAMETER	push
		A switch parameter to indicate you would like to push your changes.
		If staged changes are committed and push is provided, git push will be called once the commit is complete.
	
	.INPUTS
		None. You cannot pipe objects to git-Stage
	
	.EXAMPLE
		PS C:\> git-Stage -p
	
	DESCRIPTION
	-----------
	This example is the one I most commonly use. 
	It shows me the repository status, then asks if I want to stage/commit.
	Once the commit is complete, the changes are pushed to the remote.
#>
function git-Stage([bool]$stage = $FALSE, [bool]$commit = $FALSE, [switch]$push, [switch]$force){
	if($force -ne $true){
		git status

		if(!$stage){
			$userInput = Read-Host 'Proceed with staging? (y/n)'
		
			$stage = [string]::Compare($userInput, 'y', $TRUE) -eq 0
		}
	}
	else {
		$stage = $true;
		$commit = $true;
	}

	if($stage){
		<#
			If we are staging after resolving a merge conflict, there may be some .orig files left over.
			We don't want to commit those files, so let's make there are none to stage.
		#>
		get-childitem . -recurse -include *.orig -force | remove-item
		
		git add --all
		
		git status
		
		if(!$commit){
			$userInput = Read-Host 'Are you ready to commit? (y/n)'
			
			$commit = [string]::Compare($userInput, 'y', $TRUE) -eq 0
		}
		
		if($commit){
			if((Test-Path "commit-message.md" -PathType Leaf) -eq $true){
				git commit -eF .\commit-message.md

				$userInput = Read-Host 'Do you want to clear the commit message? (y/n)'
			
				$clearCommitMessage = [string]::Compare($userInput, 'y', $TRUE) -eq 0

				if($clearCommitMessage -eq $true){
					Remove-Item commit-message.md
				}
			}
			else{
				git commit
			}
			
			if($push -eq $true){
				git push
			}
		}
	}
}
Set-Alias gst git-Stage

<#
	.SYNOPSIS
		Performs functions to delete a branch both locally and on the remote.

	.DESCRIPTION
		By default the function will delete the indicated branch after switching to the repository's main branch.
		If the branch is un-merged without the force switch applied, the delete will not be performed.
		Optionally, you can provide the remote switch as well to delete the branch on the remote at the same time.
		If you provide the remote switch, but the branch either isn't merged, or the force switch wasn't supplied,
			then the remote branch will not be deleted.

	.PARAMETER  branchName
		The name of the branch you would like to delete

	.PARAMETER  switchToMaster
		This is true by default, in order to switch to the repository's main branch before a branch is deleted.
		
	.PARAMETER	remote
		Switch parameter indicating that the remote branch should also be deleted at the same time.
	
	.PARAMETER	force
		This overrides the error thrown if a branch is un-merged and will force the branch to be deleted.

	.EXAMPLE
		PS C:\> git-Delete feature-some-stuff -remote -force
		
	DESCRIPTION
	-----------
	
	This will delete the branch feature-some-stuff, regardless of if the branch is merged into a parent or not.
	This will also delete the feature-some-stuff branch on the remote.

	.EXAMPLE
		PS C:\> Get-Something 'One value' 32

	.INPUTS
		None. You cannot pipe to git-Delete
#>
function git-Delete([string]$branchName, [bool]$switchToMaster = $true, [switch]$remote, [switch]$force){
	$mainBranch = (git branch -r | Select-String -Pattern 'HEAD -> (.*)').Matches.Groups[1].Value.Replace("origin/", "")

	if($branchName -ieq $mainBranch){
		throw "You cannot delete the $mainBranch branch. Bad user. Bad.";
	}

	if($switchToMaster){
		git checkout $mainBranch
	}
	
	$branchExists = check-BranchExists $branchName -localOnly;
	if($branchExists -eq $true){
		$branchMerged = check-BranchMerged $branchName;
	}
	else{
		$branchMerged = $true; #Because if it doesn't exist locally, we don't care about its merged status.
	}
	
	if($branchExists -eq $true){
		if($force -eq $TRUE){
			git branch -D $branchName;
		}
		elseif($branchMerged -eq $true){
			git branch -d $branchName;
		}
		else{
			Write-Host "$branchName is not merged, and you may potentially lose work.";
			Write-Host "If you are certain you want to delete this branch, run the command with the -force switch";
		}
	}
	else{
		Write-Host "$branchName does not exist locally.";
	}
	
	if($remote -eq $TRUE -and ($branchMerged -eq $true -or $force -eq $true)){
		git push origin :$branchName;
	}
	elseif($remote -eq $true){
		Write-Host "$branchName was not able to be deleted locally, so the remote branch will not be deleted.";
	}
}
Set-Alias gdb git-Delete

<#
	Switch to the source branch, call git pull.
	Switch to the target branch, call git merge {targetBranch}
#>
function git-Merge($source, $target){
	##Check if source exists
	git show-ref --verify --quiet refs/heads/$source
	$sourceExists = $?
	
	##Check if target exists
	git show-ref --verify --quiet refs/heads/$target
	$targetExists = $?
	
	if($sourceExists -and $targetExists){
		$sourceRemote = git config --get branch.$source.merge
		$sourceHasRemote = $?
		
		if($sourceHasRemote){
			git checkout $source
			git pull
		}
		
		git checkout $target
		git merge $source
	}
	elseif(!$sourceExists){
		throw 'The source branch doesn''t exist.'
	}
	else{
		throw 'The target branch doesn''t exist.'
	}
}

<#
	.SYNOPSIS
		A function to help simplifying the pull request merge process when the pull request cannot be merged on github.

	.DESCRIPTION
		This will perform all the steps instructed on github for manually merging pull requests.
		The process will stop and check to make sure that there aren't any mergin issues along the way, and will notify you
			if action is required.
			
		You can use remote branches that you haven't pulled locally.
		If the branch is remote, but doesn't exist locally, it will be created locally first before merging.
			
		This does not replace pull requests, and isn't intended to be used in situations where the pull request can be 
			automatically.

	.PARAMETER  baseBranch
		This the branch your pull request will be merging into, "master" for instance in most cases.

	.PARAMETER  headBranch
		This is the feature or fix branch that you will be merging into master.

	.EXAMPLE
		PS C:\> git-MergePullRequest -baseBranch master -headBranch fix-bug
		
	.INPUTS
		None, this function does not accept pipeline input.

#>
function git-MergePullRequest
{
	param(
		[Parameter(Mandatory = $true)]
		[string]
		$baseBranch,
		
		[Parameter(Mandatory = $true)]
		[string]
		$headBranch
	)
	begin{
		require-CleanWorking
	
		git fetch
		
		$headLocal = $false;
		$baseLocal = $false;
	
		if(check-BranchExists $headBranch -localOnly){
			$headLocal = $true;
		}
		elseif(check-BranchExists $headBranch -remoteOnly){
			$headLocal = $false;
		}
		else{
			throw "The branch $headBranch could not be found as either a local branch or a remote one."
		}
		
		if(check-BranchExists $baseBranch -localOnly){
			$baseLocal = $true;
		}
		elseif(check-BranchExists $baseBranch -remoteOnly){
			$baseLocal = $false;
		}
		else{
			throw "The branch $baseBranch could not be found as either a local branch or a remote one."
		}
		
		if($headLocal -eq $true){
			git checkout $headBranch
			git pull
		}
		else{
			git-New-Branch $headBranch -remote
		}
		
		if($baseLocal -eq $true){
			git checkout $baseBranch
			git pull
		}
		else{
			git-New-Branch $baseBranch -remote
		}
	}
	process{
		git checkout $headBranch
		git merge $baseBranch
		
		$requiresMerging = require-CleanWorking -quiet -return
		
		if($requiresMerging -eq $false){
			Write-Host 'Merge conflicts must be resolved before continuing. Please resolve conflicts and call git-MergePullRequest again.';
		}
		else{
			git checkout $baseBranch
			git merge $headBranch
			git-Stage -stage $true -commit $true -p
		}
	}
}
Set-Alias gmp git-MergePullRequest

<#
	.SYNOPSIS
		Provides functionality for creating branches in several different configurations.

	.DESCRIPTION
		Creates a new branch in the repository. 
		Including options for what/how the parent branch is chosen, as well as switches to push the new branch to the 
			remote right away.

	.PARAMETER  newBranchName
		This is the name you would like the newly created branch to have.

	.PARAMETER  baseBranchName
		This is the name of the parent branch you would like to use.
		You can specify a remote branch either with the full 'origin/name' or by providing just the name portion and 
			passing the -remote switch.
		
	.PARAMETER	remote
		This switch parameter indicates that the branch is a remote branch.
		If you use this parameter, don't use 'origin/{branchName}', only pass over the {branchName} portion.
		
	.PARAMETER	push
		This switch parameter indicates that you wish to push the new branch to the remote imediately.
		This switch will also configure the pushed branch for git pull.
		
	.PARAMETER	getBaseLatest
		This switch will either pull the base branch if it is local, or call git fetch if the base branch is used 
			with the -remote switch.

	.EXAMPLE
		PS C:\> git-New-Branch fix-error master -push -getBaseLatest
		
	DESCRIPTION
	-----------
	This will switch to the master branch, call git pull, then create a new branch called fix-error from it.
	Once the new branch is created, it is immediately pushed to the remote.

	.EXAMPLE
		PS C:\> git-New-Branch feature-developer -remote -getBaseLatest
		
	DESCRIPTION
	-----------
	This would be the command configuration for reviewing another developers work for instance.
	First, git fetch is called to pull down the remote branches.
	Next, note that when -remote is used and the baseBranchName is not provided, then the newBranchName is used for 
		both the base and new branch names.
	So a new local branch is created based on the remote branch with the same name.

	.INPUTS
		None. You cannot pipe to git-New-Branch	
#>
function git-New-Branch([string]$newBranchName, [string]$baseBranchName = $NULL, [switch]$remote, [switch]$push, [switch]$getBaseLatest){
	$remoteBranchName = $null;
	if($remote -eq $true){
		if([string]::IsNullOrEmpty($baseBranchName)){
			$baseBranchName = $newBranchName;
		}
		
		$baseBranchName = ('origin/' + $baseBranchName);
	
		if($getBaseLatest -eq $true){
			git fetch
		}
		
		git checkout -b $newBranchName $baseBranchName
		$remoteBranchName = $baseBranchName;
	}
	else{
		if($baseBranchName){
			git checkout $baseBranchName
		}
		
		if($getBaseLatest -eq $true){
			git pull
		}
		
		git checkout -b $newBranchName
		$remoteBranchName = $newBranchName;
	}
	
	if($push -eq $true){
		iex "git push origin $($newBranchName):$($remoteBranchName) --set-upstream"
	}
}
Set-Alias gnb git-New-Branch

<#
	.SYNOPSIS
		This is a very much alpha version function, that will allow for creating a temporary copy of your repository.
		This function is still under testing and has not been verified to work for all scenarios.

	.DESCRIPTION
		This idea with this functionality is that it allows you to view/work on two or more branches at once.
		It does this by creating a temporary copy of the repository appending '-{branchName}' onto it's name.
		This temporary copy uses your working directory copy 'C:\_GIT\{RepoName}' as its remote.
		This means that the functions of GitUtil will work the same with your temporary copy with your working 
			directory as origin instead of git hub.

	.PARAMETER  branchName
		This should be the name of a local branch in your repository.
		It will be used to identify the temp copy of your repo and also,
			the temp copy will checkout this branch when it is created.

	.PARAMETER  repoPath
		This is an optional parameter as long as you are in the base directory of your repo.
		If not, you will need to provide the full path to where the repo you want to copy
			is located.

	.EXAMPLE
		PS C:\> git-Temp master 'c:\_git\dailycash'
		
	DESCRIPTION
	-----------
	This will create a temporary copy of daily cash and navigate there under the master branch.
#>
function git-Temp([string]$branchName, [string]$repoPath = $NULL){
	if(-not [string]::IsNullOrEmpty($branchName)){
		$gitDir = "C:\_GIT";
		$tempDir = "C:\_GIT\Temp";
		$gitDirExists = Test-Path $gitDir;
		$tempDirExists = Test-Path $tempDir;
		
		if($gitDirExists -ne $true){
			New-Item -type directory -Path $gitDir;
		}
		
		if($tempDirExists -ne $true){
			New-Item -type directory -Path $tempDir;
		}
		
		if([string]::IsNullOrEmpty($repoPath)){
			$repoPath = Get-Location;
		}
		
		$repoName = ($repoPath | Split-Path -Leaf).Replace(" ", "-");
		$tempRepoName = $repoName + "-" + $branchName;
		$tempRepoPath = [System.IO.Path]::Combine($tempDir, $tempRepoName);
		$tempRepoExists = Test-Path $testRepoPath;
		
		if($tempRepoExists -ne $true){
			cd $tempDir
			git clone $repoPath $tempRepoPath
			
			cd $tempRepoPath
			git-New-Branch $branchName $branchName -r
		}
		else{
			echo 'The temporary repository for this branch already exists.';
			cd $tempRepoPath
		}
	}
	else{
		throw 'A branch name is required to create the temporary repository.';
	}
}
Set-Alias gtp git-Temp

<#
	.SYNOPSIS
		This function simplifies the procedure of stashing your working directory changes.

	.DESCRIPTION
		This function simplifies the procedure of stashing your working directory changes.
		This is equivilant to git stash save --include-untracked $message, which will
			stash your modified and untracked files as well as the index, and also
			a message if provided.

	.PARAMETER  message
		An optional parameter to store a custom message with the stash.

	.PARAMETER  ParameterB
		The description of the ParameterB parameter.

	.EXAMPLE
		PS C:\> git-Shelve 'Stopping feature production to do a bug fix.'
		
	DESCRIPTION
	-----------
	Shelves the current working directory with the indicated message.
#>
function git-Shelve ([string] $message = $null){
	git stash save --include-untracked $message
}
Set-Alias gsh git-Shelve

<#
	.SYNOPSIS
		Used to apply stashes back to your working directory.

	.DESCRIPTION
		Stashes can be re-applied either on top of the working directory on the current branch,
			or under a new branch created from the stash.
			
		Unlike the original git command, when a stash is applied as a new branch here it is applied on top a new branch
			that is based on the baseBranchName parameter or HEAD if none specified.

	.PARAMETER  index
		This optional parameter indicates which stash you would like to re-apply.
		If index is not supplied, the first stash in the stack is used.

	.PARAMETER  branchName
		If branchName is supplied, then the stash will be re-applied to a new branch with the given name.
		
	.PARAMETER	baseBranchName
		If baseBranchName is supplied, then this is the branch that the new branch to which the stash is applied
			will be based on.

	.PARAMETER dropStash
		Use this switch when applying a stash to your current branch in order to delete the stash, after it is applied.

	.EXAMPLE
		PS C:\> git-Un-Shelve -index 1 -branchName feature-new-feature
		
	DESCRIPTION
	-----------
	This will unshelve the stash at index 1 and restore it to a new branch called feature-new-feature.

	.INPUTS
		None. You cannot pipe to git-Un-Shelve
#>
function git-Un-Shelve([System.Nullable``1[[System.Int32]]] $index = $null, [string]$branchName = $null, [string]$baseBranchName = $null, [switch] $dropStash){
	$gitCommand = 'git stash ';
	$stashSelector = $null;
	if($index -ne $null){
		$stashSelector = " 'stash@{" + $index + "}'";
	}

	$applyCommand = 'apply --index';
	if(-not [string]::IsNullOrEmpty($branchName)){
		$baseTypeFlag = $null;
	
		if([string]::IsNullOrEmpty($baseBranchName)){
			$baseBranchName = git symbolic-ref HEAD
			if(-not [string]::IsNullOrEmpty($baseBranchName)){
				$baseBranchName = ($baseBranchName | Split-Path -Leaf)
			}
			else{
				throw 'A base branch name must be supplied if you are on a detached head.'
			}
		}
		
		if(check-BranchExists $baseBranchName -remoteOnly){
			$baseTypeFlag = '-remote';
		}
		elseif(check-BranchExists $baseBranchName -localOnly){
			$baseTypeFlag = '';
		}
		else{
			throw "$baseBranchName does not appear to exist, please check the base branch name and try again.";
		}
		
		if(check-BranchExists $branchName -localOnly){
			$retryUnShelveCommand = 'git-Un-Shelve';
			if($index -ne $null){
				$retryUnShelveCommand += " -index $index";
			}
			if($dropStash -eq $true){
				$retryUnShelveCommand += ' -dropStash';
			}
			
			throw "$branchName already exists. Please switch to that branch using ''git checkout $branchName'' and try running $retryUnShelveCommand again."
		}
		
		if($branchName -imatch 'origin/'){
			throw "$branchName is invalid. A new local branch name must be supplied."
		}
		
		git-New-Branch -newBranchName $branchName -baseBranchName $baseBranchName
		
		#Right now git-New-Branch will switch to the new branch when it's created, but I'll add this in case that changes in the future.
		if((git symbolic-ref HEAD | Split-Path -Leaf) -ne $branchName){
			git checkout $branchName
		}
		
#		if($baseBranchName -not -ieq (git symbolic-ref HEAD | Split-Path -Leaf)){
#			
#		}
#	
#		$applyCommand = 'branch ' + $branchName + ' --index ';
	}
	
	if($dropStash -eq $true){
		$applyCommand = 'pop --index';
	}
	
	iex ($gitCommand + $applyCommand + $stashSelector)
}
Set-Alias gus git-Un-Shelve

<#
	.SYNOPSIS
		Performs a deep clean of the working directory.

	.DESCRIPTION
		This functionality will un-stage all files in the index, reset tracked files back to HEAD,
			and also clean the working directory of any un-tracked/ignored files.
		This is usefull to run when you have corrupted your working directory,
			want to clear out things like the bin/obj folders,
			and is especially usefull for running right before a build/deploy.

	.PARAMETER  force
		If this switch parameter is not passed, a warning will be displayed that the workign directory
			is about to be cleaned and asks that you confirm the action.

	.EXAMPLE
		PS C:\> git-Reset -f
		
	DESCRIPTION
	-----------
	This will deep clean the working directory with no warning before hand since the -f switch is supplied.

	.INPUTS
		None. You cannot pipe to git-Reset.
#>
function git-Reset([switch] $force){
	$reset = $false;
	if($force -ne $true){
		$userInput = Read-Host 'This will clean the working directory and index reseting back to the last commit. Are you sure you want to continue? (y/n)';
		$reset = [string]::Compare($userInput, 'y', $TRUE) -eq 0
	}
	else{
		$reset = $true;
	}
	
	if($reset){
		git reset HEAD
		git checkout -- *
		git clean -d -f -x
	}
}
Set-Alias grs git-Reset

<#
	.SYNOPSIS
		A shorcut for git log which displays a similar format to a network graph in git hub.

	.DESCRIPTION
		A shorcut for git log which displays a similar format to a network graph in git hub.

	.EXAMPLE
		PS C:\> git-Tree
		
	DESCRIPTION
	-----------
	This will display the log of commits showing the location of branches,
		very similar to how the git hub network graph looks.

	.EXAMPLE
		PS C:\> glt
	
	DESCRIPTION
	-----------
	The same as git-Tree but using the shorter alias.

	.INPUTS
		None. You cannot pipe to git-Tree.
#>
function git-Tree(){
	git log --graph --all --decorate --oneline
}
Set-Alias glt git-Tree

<#
	.SYNOPSIS
		This is just a quick way of git branch since I've aliased it as gbr.

	.DESCRIPTION
		This is just a quick way of git branch since I've aliased it as gbr.
		
	.PARAMETER	commandParams
		Parameters you want to pass to the git branch command such as --all, -r, etc.
		
#>
function git-Branches([string]$commandParams = $null){
	$branchCommand = 'git branch';
	if($commandParams -ne $null){
		$branchCommand += (' ' + $commandParams);
	}
	
	iex $branchCommand
}
Set-Alias gbr git-Branches

<#
	.SYNOPSIS
		This is just a quick way of git checkout since I've aliased it as gco.

	.DESCRIPTION
		This is just a quick way of git checkout since I've aliased it as gco.
	
	.PARAMETER	commandParams
		Parameters you want to pass to the git checkout command such as -b.
#>
function git-Checkout-Branch([string]$branchName, [string]$commandParams){
	$checkoutCommand = "git checkout $branchName";
	if($commandParams -ne $null){
		$checkoutCommand += (' ' + $commandParams);
	}
	
	iex $checkoutCommand
}
Set-Alias gco git-Checkout-Branch

<#
	.SYNOPSIS
		This command opens a Vim editor to the commit-message.md file.

	.DESCRIPTION
		This command opens a Vim editor to the commit-message.md file.
	
	.PARAMETER	commandParams
		Parameters you want to pass to the git checkout command such as -b.
#>
function git-Edit-Commit-Document([string]$branchName, [string]$commandParams){
	iex "vim commit-message.md"
}
Set-Alias gec git-Edit-Commit-Document

# Tab completion borrowed from PSGet, which is derived from posh-git
$tcBackup = 'PowerShell_TabExpansionBackup'
if((Test-Path Function:\TabExpansion) -and !(Test-Path Function:\$tcBackup)){
	Rename-Item Function:\TabExpansion $tcBackup
}

$module = $MyInvocation.MyCommand.ScriptBlock.Module 
$module.OnRemove = {
    Write-Verbose "Revert tab expansion back"
    Remove-Item Function:\TabExpansion
    if (Test-Path Function:\$tcBackup)
    {
        Rename-Item Function:\$tcBackup Function:\TabExpansion
    }
}

function global:TabExpansion($line, $lastWord) {
	function Get-Branches ([string]$lastWord, [switch]$all, [switch]$remote){
		$branchCommand = 'git branch';
		if($all -eq $true){
			$branchCommand += ' --all';
		}
		elseif($remote -eq $true){
			$branchCommand += ' -r';
		}
	
		$branchNameArray = iex $branchCommand | %{ ($_ | split-path -Leaf).Replace(" ", "").Replace("*", "")} | select -Unique
		
		if(-not [string]::IsNullOrEmpty($lastWord)){
			$branchNameArray = $branchNameArray -imatch $lastWord;
		}
		
		return $branchNameArray;
	}
	
	$useDefaultExpansion = $false;
	if(!$lastWord.StartsWith('-')){
		if($line -imatch "^$(get-aliaspattern git-delete) (.*)" `
			-or $line -imatch "^$(get-aliaspattern git-New-Branch) (.*)" `
			-or $line -imatch "^$(get-aliaspattern git-Un-Shelve) (.*)"){
			Get-Branches $lastWord -all | sort -Unique
		}
		elseif($line -imatch "^$(get-aliaspattern git-MergePullRequest) (.*)"){
			Get-Branches $lastWord -remote | sort -Unique
		}
		elseif($line -imatch "^$(get-aliaspattern git-qa) (.*)" `
				-or $line -imatch "^$(get-aliaspattern git-Temp) (.*)" `
				-or $line -imatch "^$(get-aliaspattern git-Checkout-Branch) (.*)"){
			Get-Branches $lastWord | sort -Unique
		}
		else{
			$useDefaultExpansion = $true
		}
	}
	else{
		$useDefaultExpansion = $true
	}
	
	if($useDefaultExpansion -eq $true -and (Test-Path Function:\$tcBackup)){
		& $tcBackup $line $lastWord
	}

#	if(($line -imatch "^$(get-aliaspattern git-delete) (.*)" `
#			-or $line -imatch "^$(get-aliaspattern git-New-Branch) (.*)" `
#			-or $line -imatch "^$(get-aliaspattern git-qa) (.*)" `
#			-or $line -imatch "^$(get-aliaspattern git-MergePullRequest) (.*)") `
#		-and !$lastWord.StartsWith('-')){
#		Get-Branches $lastWord | %{ $_ } | sort -Unique
#	}
#	elseif(Test-Path Function:\$tcBackup){
#		& $tcBackup $line $lastWord
#	}
}

## Exporting module member functions
Export-ModuleMember -Function @('git-StageDeleted', 
								'git-Stage', 
								'git-Delete', 
								'git-New-Branch', 
								'git-Temp',
								'git-Shelve',
								'git-Un-Shelve',
								'git-Reset',
								'git-Tree',
								'git-Branches',
								'git-Checkout-Branch'
								'git-MergePullRequest',
								'git-Edit-Commit-Document') `
					-Alias @('gsd',
								'gst',
								'gdb',
								'gnb',
								'gtp',
								'gsh',
								'gus',
								'grs',
								'glt',
								'gbr',
								'gco',
								'gmp',
								'gec')
