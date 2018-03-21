#!/bin/bash

set -e
set -x
set -u

sync_json=$PWD/sync.json
sync_directory=
remote_origin=origin
remote_sync=sync
remote_nodes=($remote_origin $remote_sync)

function check_require(){
        ##check getopt
        local out=$(getopt -T)
        if (( $? != 4 )) && [[ -n $out ]]; then
                echo >&2 "I require GNU getopt but it's not installed.  Aborting."
                exit 1
        fi
        ##check jq
        command -v jq >/dev/null 2>&1 || { echo >&2 "I require jq but it's not installed.  Aborting."; exit 1; }
        ##check git
        command -v git >/dev/null 2>&1 || { echo >&2 "I require git but it's not installed.  Aborting."; exit 1; }

        ##check dns/internet
        case "$(curl -s --max-time 2 -I https://google.com | sed 's/^[^ ]*  *\([0-9]\).*/\1/; 1q')" in
                [23])
                        ;;
                5)
                        echo >&2 "The web proxy won't let us through"; exit 1 ;;
                *)
                        echo >&2 "The network is down or very slow"; exit 1 ;;
        esac


}

function _check_remote(){
        local _remote=$1
        local i=0

        for g in $(jq -r ".repos | .[] | .$_remote" $sync_json)
        do
                exist=$(git ls-remote -h  $g -q)
                [ -z $exist ] || { echo >&2 "I found $g not exist. Aborting." exit 1;}
                if [ "$_remote" == "$remote_sync" ];then
                        #check track remote branch
                        for b in $(jq -r ".repos | .[$i] | .branch | .[]" $sync_json)
                        do
                                exist_branch=$(git ls-remote -h $g | grep "refs/heads/$b")
                                [ ! -z "$exist_branch" ] || { echo >&2 "I found the branch $b of $g not exist. Aborting." exit 1;}

                        done
                fi
                i=$(( $i + 1 ))
        done


}

function check_remotes(){

        for rn in ${remote_nodes[@]}
        do
                _check_remote $rn
        done
}

function check_directory(){
        local isin_git
        local directory

        directory=$(jq -r ".directory" $sync_json)
        case "$directory" in
                "."|"./")
                        sync_directory=$PWD ;;
                ".."|"../")
                        sync_directory=$(dirname $PWD) ;;
                *)
                        sync_directory=$directory ;;
        esac

        [ ! -d "$sync_directory" ] && mkdir -p $sync_directory
        #check not in git repo
        cd $sync_directory
        isin_git=$(git rev-parse --is-inside-work-tree || echo "false")
        [ "$isin_git" == "true" ] && { echo >&2 "I cant sync repos into $_sync_dir(it's a git repo).  Aborting."; exit 1; }
        echo "go next0"
}

function pull_sync(){
        local repos_num=0
        local repos_count=0
        local branch_num=0
        local branch_count=0

        local _dirname
        local _origin_url
        local _sync_url
        local _branch


        local i=0;
        local j=0;

        repos_count=$(jq -r '.repos | length'  $sync_json)
        repos_num=$(($repos_count-1))

        [ "$repos_num" == "-1" ] && { echo >&2 "repos of $sync_json is empty. Aborting";exit 1; }

        for i in $(seq 0 $repos_num)
        do
                _dirname=$(jq -r ".repos|.[$i]|.dirname" $sync_json)
                _origin_url=$(jq -r ".repos|.[$i]|.origin" $sync_json)
                _sync_url=$(jq -r ".repos|.[$i]|.sync" $sync_json)

                branch_count=$(jq -r ".repos|.[$i]|.branch|length" $sync_json)
                branch_num=$(($branch_count-1))

                for j in $(seq 0 $branch_num)
                do
                        _branch=$(jq -r ".repos|.[$i]|.branch|.[$j]" $sync_json)
                        _pull_sync $_dirname $_origin_url $_sync_url $_branch
                done

        done

}

function _pull_sync(){

        local _dirname=$1
        local _origin_url=$2
        local _sync_url=$3
        local _branch=$4

        local _full_path
        local isin_git

        [ -z $_dirname ] && { echo >&2 "dirname cant be empty in $sync_json.  Aborting.";exit 1; }
        _full_path=$sync_directory/$_dirname


        [ ! -d "$_full_path" ] && mkdir -p $_full_path
        cd $_full_path
        isin_git=$(git rev-parse --is-inside-work-tree || echo "false" )
        if [ "$isin_git" == "true" ];then
                checkSync_remoteOfRepo $_full_path $remote_origin $_origin_url $_branch
                checkSync_remoteOfRepo $_full_path $remote_sync $_sync_url $_branch
        else
                [ $(ls -A $_full_path) ] && { echo >&2 "$_full_path is not empty.  Aborting";exit 1; }
                cd $_full_path
                git clone $_origin_url . --branch $_branch
                [ "$(git rev-parse --verify --quiet $_branch)" == "" ] && git branch $_branch
                git checkout  $_branch
                git remote add $remote_sync $_sync_url
                git pull $remote_sync $_branch
                # track keywords:'sync-'
                git branch --track sync-$_branch  $remote_sync/$_branch
                git push -u $remote_origin $_branch
        fi

        cd $_full_path

        if [ "$(git rev-parse --verify --quiet $_branch)" == "" ];then
                git checkout -b $_branch
                git pull $remote_origin $_branch
        fi

        if [ "$(git rev-parse --verify --quiet sync-$_branch)" == ""  ];then
                git pull $remote_sync $_branch
                git branch --track sync-$_branch  $remote_sync/$_branch
                git push -u $remote_origin $_branch
        fi

        git checkout sync-$_branch
        git pull $remote_sync $_branch

        git checkout $_branch
        git pull $remote_origin $_branch
        git merge sync-$_branch
        git push $remote_origin $_branch
}

function checkSync_remoteOfRepo(){
        local _fullpath=$1
        local _remote_name=$2
        local _remote_url=$3
        local _branch=$4

        local existed_url
        local existed_remote
        local existed_remote_num

        [ -z $_fullpath ] && { echo >&2 "_fullpath is empty"; exit 1; }
        [ -z $_remote_name ] && { echo >&2 "_remote_name is empty"; exit 1; }
        [ -z $_remote_url ] && { echo >&2 "_remote_url is empty"; exit 1; }

        cd $_fullpath

        local_existed_remote_num=$(git remote | grep $_remote_name | wc -l | tr -d ' ')
        if [ "$local_existed_remote_num" == "1"  ];then
                existed_remote=$(git remote | grep $_remote_name)
                if [ "$existed_remote" == "$_remote_name" ];then
                        existed_url=$(git remote get-url $_remote_name)
                        [ "$existed_url" != "$_remote_url" ] && exit "$_fullpath existing another repo.  Aborting."
                        echo "go next1"
                else
                        # not test
Hongshuns-MacBook-Air:temp hongshunyang$ ls
core		dictionaries	dsserver	sdkjs		sdkjs-plugins	sync.json	sync.sh		web-apps
Hongshuns-MacBook-Air:temp hongshunyang$ ls
core		dictionaries	dsserver	sdkjs		sdkjs-plugins	sync.json	sync.sh		web-apps
Hongshuns-MacBook-Air:temp hongshunyang$ rm -rf core dictionaries dsserver sdkjs*
Hongshuns-MacBook-Air:temp hongshunyang$ ls
sync.json	sync.sh		web-apps
Hongshuns-MacBook-Air:temp hongshunyang$ rm -rf web-apps
Hongshuns-MacBook-Air:temp hongshunyang$ ls
sync.json	sync.sh
Hongshuns-MacBook-Air:temp hongshunyang$ git status
fatal: Not a git repository (or any of the parent directories): .git
Hongshuns-MacBook-Air:temp hongshunyang$ cd ..
Hongshuns-MacBook-Air:wholerenDevTeam hongshunyang$ ls
cas			frappe			metabase		onlyoffice		soa.wholeren.com	uikit			webpack			wholecms-platform
erpnext			lay			nextcloud		readme			temp			webim			wholecloud-platform
Hongshuns-MacBook-Air:wholerenDevTeam hongshunyang$ cd onlyoffice/
Hongshuns-MacBook-Air:onlyoffice hongshunyang$ ls
core					documentserver				sdkjs					sync.sh
dictionaries				dsserver				sdkjs-plugins				web-apps
docker-onlyoffice-documentserver	onlyoffice-documentserver-platform	sync.json
Hongshuns-MacBook-Air:onlyoffice hongshunyang$ ls
core					documentserver				sdkjs					sync.sh
dictionaries				dsserver				sdkjs-plugins				web-apps
docker-onlyoffice-documentserver	onlyoffice-documentserver-platform	sync.json
Hongshuns-MacBook-Air:onlyoffice hongshunyang$ rm sync.json
Hongshuns-MacBook-Air:onlyoffice hongshunyang$ ls
core					docker-onlyoffice-documentserver	dsserver				sdkjs					sync.sh
dictionaries				documentserver				onlyoffice-documentserver-platform	sdkjs-plugins				web-apps
Hongshuns-MacBook-Air:onlyoffice hongshunyang$ cd ..
Hongshuns-MacBook-Air:wholerenDevTeam hongshunyang$ ls
cas			frappe			metabase		onlyoffice		soa.wholeren.com	uikit			webpack			wholecms-platform
erpnext			lay			nextcloud		readme			temp			webim			wholecloud-platform
Hongshuns-MacBook-Air:wholerenDevTeam hongshunyang$ cd temp/
Hongshuns-MacBook-Air:temp hongshunyang$ ls
sync.json	sync.sh
Hongshuns-MacBook-Air:temp hongshunyang$ vim sync.sh
Hongshuns-MacBook-Air:temp hongshunyang$ clear
Hongshuns-MacBook-Air:temp hongshunyang$ ls
sync.json	sync.sh
Hongshuns-MacBook-Air:temp hongshunyang$ cat sync.sh
#!/bin/bash

set -e
set -x
set -u

sync_json=$PWD/sync.json
sync_directory=
remote_origin=origin
remote_sync=sync
remote_nodes=($remote_origin $remote_sync)

function check_require(){
	##check getopt
	local out=$(getopt -T)
	if (( $? != 4 )) && [[ -n $out ]]; then
		echo >&2 "I require GNU getopt but it's not installed.  Aborting."
		exit 1
	fi
	##check jq
	command -v jq >/dev/null 2>&1 || { echo >&2 "I require jq but it's not installed.  Aborting."; exit 1; }
	##check git
	command -v git >/dev/null 2>&1 || { echo >&2 "I require git but it's not installed.  Aborting."; exit 1; }

	##check dns/internet
	case "$(curl -s --max-time 2 -I https://google.com | sed 's/^[^ ]*  *\([0-9]\).*/\1/; 1q')" in
  		[23])
			;;
  		5)
			echo >&2 "The web proxy won't let us through"; exit 1 ;;
  		*)
			echo >&2 "The network is down or very slow"; exit 1 ;;
	esac


}

function _check_remote(){
	local _remote=$1
	local i=0

	for g in $(jq -r ".repos | .[] | .$_remote" $sync_json)
	do
		exist=$(git ls-remote -h  $g -q)
		[ -z $exist ] || { echo >&2 "I found $g not exist. Aborting." exit 1;}
		if [ "$_remote" == "$remote_sync" ];then
			#check track remote branch
			for b in $(jq -r ".repos | .[$i] | .branch | .[]" $sync_json)
			do
				exist_branch=$(git ls-remote -h $g | grep "refs/heads/$b")
				[ ! -z "$exist_branch" ] || { echo >&2 "I found the branch $b of $g not exist. Aborting." exit 1;}

			done
		fi
		i=$(( $i + 1 ))
	done


}

function check_remotes(){

	for rn in ${remote_nodes[@]}
	do
		_check_remote $rn
	done
}

function check_directory(){
	local isin_git
	local directory

	directory=$(jq -r ".directory" $sync_json)
	case "$directory" in
		"."|"./")
			sync_directory=$PWD ;;
		".."|"../")
			sync_directory=$(dirname $PWD) ;;
		*)
			sync_directory=$directory ;;
	esac

	[ ! -d "$sync_directory" ] && mkdir -p $sync_directory
	#check not in git repo
	cd $sync_directory
	isin_git=$(git rev-parse --is-inside-work-tree || echo "false")
	[ "$isin_git" == "true" ] && { echo >&2 "I cant sync repos into $_sync_dir(it's a git repo).  Aborting."; exit 1; }
	echo "go next0"
}

function pull_sync(){
	local repos_num=0
	local repos_count=0
	local branch_num=0
	local branch_count=0

	local _dirname
	local _origin_url
	local _sync_url
	local _branch


	local i=0;
	local j=0;

	repos_count=$(jq -r '.repos | length'  $sync_json)
	repos_num=$(($repos_count-1))

	[ "$repos_num" == "-1" ] && { echo >&2 "repos of $sync_json is empty. Aborting";exit 1; }

	for i in $(seq 0 $repos_num)
	do
		_dirname=$(jq -r ".repos|.[$i]|.dirname" $sync_json)
		_origin_url=$(jq -r ".repos|.[$i]|.origin" $sync_json)
		_sync_url=$(jq -r ".repos|.[$i]|.sync" $sync_json)

		branch_count=$(jq -r ".repos|.[$i]|.branch|length" $sync_json)
		branch_num=$(($branch_count-1))

		for j in $(seq 0 $branch_num)
		do
			_branch=$(jq -r ".repos|.[$i]|.branch|.[$j]" $sync_json)
			_pull_sync $_dirname $_origin_url $_sync_url $_branch
		done

	done

}

function _pull_sync(){

	local _dirname=$1
	local _origin_url=$2
	local _sync_url=$3
	local _branch=$4

	local _full_path
	local isin_git

	[ -z $_dirname ] && { echo >&2 "dirname cant be empty in $sync_json.  Aborting.";exit 1; }
	_full_path=$sync_directory/$_dirname


	[ ! -d "$_full_path" ] && mkdir -p $_full_path
	cd $_full_path
	isin_git=$(git rev-parse --is-inside-work-tree || echo "false" )
	if [ "$isin_git" == "true" ];then
		checkSync_remoteOfRepo $_full_path $remote_origin $_origin_url $_branch
		checkSync_remoteOfRepo $_full_path $remote_sync $_sync_url $_branch
	else
		[ $(ls -A $_full_path) ] && { echo >&2 "$_full_path is not empty.  Aborting";exit 1; }
		cd $_full_path
		git clone $_origin_url . --branch $_branch
		[ "$(git rev-parse --verify --quiet $_branch)" == "" ] && git branch $_branch
		git checkout  $_branch
		git remote add $remote_sync $_sync_url
		git pull $remote_sync $_branch
		# track keywords:'sync-'
		git branch --track sync-$_branch  $remote_sync/$_branch
		git push -u $remote_origin $_branch
	fi

	cd $_full_path

	if [ "$(git rev-parse --verify --quiet $_branch)" == "" ];then
		git checkout -b $_branch
		git pull $remote_origin $_branch
	fi

	if [ "$(git rev-parse --verify --quiet sync-$_branch)" == ""  ];then
		git pull $remote_sync $_branch
		git branch --track sync-$_branch  $remote_sync/$_branch
		git push -u $remote_origin $_branch
	fi

	git checkout sync-$_branch
	git pull $remote_sync $_branch

	git checkout $_branch
	git pull $remote_origin $_branch
	git merge sync-$_branch
	git push $remote_origin $_branch
}

function checkSync_remoteOfRepo(){
	local _fullpath=$1
	local _remote_name=$2
	local _remote_url=$3
	local _branch=$4

	local existed_url
	local existed_remote
	local existed_remote_num

	[ -z $_fullpath ] && { echo >&2 "_fullpath is empty"; exit 1; }
	[ -z $_remote_name ] && { echo >&2 "_remote_name is empty"; exit 1; }
	[ -z $_remote_url ] && { echo >&2 "_remote_url is empty"; exit 1; }

	cd $_fullpath

	local_existed_remote_num=$(git remote | grep $_remote_name | wc -l | tr -d ' ')
	if [ "$local_existed_remote_num" == "1"  ];then
		existed_remote=$(git remote | grep $_remote_name)
		if [ "$existed_remote" == "$_remote_name" ];then
			existed_url=$(git remote get-url $_remote_name)
			[ "$existed_url" != "$_remote_url" ] && exit "$_fullpath existing another repo.  Aborting."
			echo "go next1"
		else
			# not test
			echo "so many remotes with same string:$_remote_name,Please change directory of $sync_json"
			exit 1
		fi
	else
		# not test
		if [ "$local_existed_remote_num" == "0" ];then
			git remote add $_remote_name $_remote_url
			echo "go next2"
		else
			echo "so many remotes with same string:$_remote_name,Please change directory of $sync_json"
			exit 1
		fi
	fi
}


function run(){
	[ -f "$sync_json" ] || { echo >&2 "$sync_json not exist!  Aborting.";exit 1; }
	check_remotes
	check_directory
	pull_sync
}


######------------------------#########

O=`getopt -o f: --long syn-json: -- "$@"` || exit 1
eval set -- "$O"
# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -f|--sync-json)
            case "$2" in
                "") shift 2 ;;
                *) sync_json=$2 ; shift 2 ;;
            esac ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

######------------------------#########
check_require
run
