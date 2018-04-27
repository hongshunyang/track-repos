#!/bin/bash

#set -e
#set -x
#set -u

#origin: your repos
#sync: open source repos(was tracked)

#基于同步过来的 tag 创建新tag
#1 同步sync的tag到origin：保持tag同名
# done by sync.sh
# ------------------------------------------------------------------
#2 创建基于tag的开发分支develop-tag（如果remote sync的tag 是基于remote 的 master 创建，这里develop-tag 就是master）
# git checkout -b develop-tag v0.9
#3 合并从remote sync新fetch的tag 到develop-tag
# git merge <v1.0>
#4 打标签
# git tag -a v1.0.P1 -m 'patched tag v1.0'
#5 push 新标签到remote origin
# git push origin v1.0.P1
#6 push 本地分支develop-tag 到remote origin
# git push origin develop-tag



sync_json=$PWD/sync.json
sync_directory=$PWD
remote_origin=origin
remote_sync=sync
remote_nodes=($remote_origin $remote_sync)

#dont change
default_branch_when_branchIsEmpty=master

auto_commit_origin=1
auto_pull_origin=1
auto_merge_sync=1
auto_push_origin=1

function print_msg(){
	printf %.s- {1..50}
	echo
	echo $1
}
function print_(){
	printf %.s- {1..50}
	echo
}

function check_require(){
	##check getopt
	local out=$(getopt -T)
	if (( $? != 4 )) && [[ -n $out ]]; then
		print_msg  "I require GNU getopt but it's not installed.  Aborting."
		exit 1
	fi
	##check jq
	command -v jq >/dev/null 2>&1 || { print_msg  "I require jq but it's not installed.  Aborting."; exit 1; }
	##check git
	command -v git >/dev/null 2>&1 || { print_msg  "I require git but it's not installed.  Aborting."; exit 1; }

	##check dns/internet
	case "$(curl -s --max-time 2 -I https://google.com | sed 's/^[^ ]*  *\([0-9]\).*/\1/; 1q')" in
  		[23])
			;;
  		5)
			print_msg  "The web proxy won't let us through"; exit 1 ;;
  		*)
			print_msg  "The network is down or very slow"; exit 1 ;;
	esac


}

function _check_remote(){
	local _remote=$1
	local i=0
	local b
	local t
	local g
	local branch_count=0
	local tag_count=0

	for g in $(jq -r ".repos | .[] | .$_remote" $sync_json)
	do
		print_ 30
		echo "Checking repos: $g"
		exist=$(git ls-remote -h  $g -q)
		[ -z $exist ] || { print_msg "I found $g not exist. Aborting."; exit 1;}
		if [ "$_remote" == "$remote_sync" ];then
			#check track remote branch
			branch_count=$(jq -r ".repos|.[$i]|.branch|length" $sync_json)
			if [ $branch_count -ge 1 ];then
				for b in $(jq -r ".repos | .[$i] | .branch | .[]" $sync_json)
				do
					echo "Checking branch: $b"
					exist_branch=$(git ls-remote -h $g | grep "refs/heads/$b")
					[ ! -z "$exist_branch" ] || { print_msg  "I found the branch $b of $g not exist. Aborting." ; exit 1;}
				done
			fi
			#check track remote tag
			tag_count=$(jq -r ".repos|.[$i]|.tag|length" $sync_json)
			if [ $tag_count -ge 1 ];then
				for t in $(jq -r ".repos | .[$i] | .tag | .[]" $sync_json)
				do
					echo "Checking tag: $t"
					exist_tag=$(git ls-remote $g -t $t | grep "refs/tags/$t")
					[ ! -z "$exist_tag" ] || { print_msg  "I found the tag $t of $g not exist. Aborting." ; exit 1;}
				done
			fi
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

        if [[ "$sync_directory" =~ ^\.\/.*  ]];then
		## ./abc
		sync_directory=$PWD/$(echo $sync_directory|tr -d "./")
	elif [[ "$sync_directory" =~ ^\.\.\/.*  ]];then
		## ../abc
		sync_directory=$(dirname $PWD)/$(echo $sync_directory|tr -d "../")
	else
		echo
	fi
	[ ! -d "$sync_directory" ] && mkdir -p $sync_directory
	#check not in git repo
	cd $sync_directory
	isin_git=$(git rev-parse --is-inside-work-tree 2>/dev/null)
	[ "$isin_git" == "true" ] && { print_msg  "I cant sync repos into $_sync_dir(it's a git repo).  Aborting."; exit 1; }
	#go next0
}

function pull_sync(){
	local repos_num=0
	local repos_count=0
	local branch_num=0
	local branch_count=0
	local tag_num=0
	local tag_count=0

	local _dirname
	local _origin_url
	local _sync_url
	local _branch
	local _tag


	local i=0;
	local j=0;
	local k=0;
	print_msg "Starting pull and sync"
	repos_count=$(jq -r '.repos | length'  $sync_json)
	repos_num=$(($repos_count-1))

	[ "$repos_num" == "-1" ] && { print_msg  "repos of $sync_json is empty. Aborting";exit 1; }

	for i in $(seq 0 $repos_num)
	do
		_dirname=$(jq -r ".repos|.[$i]|.dirname" $sync_json)
		_origin_url=$(jq -r ".repos|.[$i]|.origin" $sync_json)
		_sync_url=$(jq -r ".repos|.[$i]|.sync" $sync_json)

		##sync branch
		branch_count=$(jq -r ".repos|.[$i]|.branch|length" $sync_json)
		branch_num=$(($branch_count-1))
		if [ $branch_num -eq -1 ];then
			#default master when branch is empty
			_pull_sync_branch $_dirname $_origin_url $_sync_url $default_branch_when_branchIsEmpty
		else
			for j in $(seq 0 $branch_num)
			do
				_branch=$(jq -r ".repos|.[$i]|.branch|.[$j]" $sync_json)
				_pull_sync_branch $_dirname $_origin_url $_sync_url $_branch
			done
		fi

		##sync tag
		tag_count=$(jq -r ".repos|.[$i]|.tag|length" $sync_json)
		tag_num=$(($tag_count-1))
		if [ $tag_count -ge 1 ];then
			for k in $(seq 0 $tag_num)
			do
				_tag=$(jq -r ".repos|.[$i]|.tag|.[$k]" $sync_json)
				_pull_sync_tag $_dirname $_origin_url $_sync_url $_tag
			done
		fi

	done
	print_msg "Pull and sync end."

}

function _pull_sync_tag(){

	local _dirname=$1
	local _origin_url=$2
	local _sync_url=$3
	local _tag=$4

	local _full_path
	local isin_git

	print_

	[ -z $_dirname ] && { print_msg  "dirname cant be empty in $sync_json.  Aborting.";exit 1; }
	_full_path=$sync_directory/$_dirname

	[ ! -d "$_full_path" ] && mkdir -p $_full_path
	cd $_full_path
	isin_git=$(git rev-parse --is-inside-work-tree 2>/dev/null )
	if [ "$isin_git" == "true" ];then
		_verify_remote $_full_path $remote_origin $_origin_url
		_verify_remote $_full_path $remote_sync $_sync_url
	else
		[ $(ls -A $_full_path) ] && { print_msg  "$_full_path is not empty.  Aborting";exit 1; }
		cd $_full_path
		git clone $_origin_url .
		git remote add $remote_sync $_sync_url
	fi

	cd $_full_path
	#not have tag
	if [ "$(git rev-parse --verify --quiet $_tag)" == "" ];then
		#must fetch from remote_sync
		git fetch $remote_sync +refs/tags/$_tag:refs/tags/$_tag
	fi
	#git push to remote_origin
	if [ "$(git rev-parse --verify --quiet $_tag)" != "" ];then
		git push $remote_origin $_tag
	fi

}

function _pull_sync_branch(){

	local _dirname=$1
	local _origin_url=$2
	local _sync_url=$3
	local _branch=$4

	local _full_path
	local isin_git

	print_

	[ -z $_dirname ] && { print_msg  "dirname cant be empty in $sync_json.  Aborting.";exit 1; }
	_full_path=$sync_directory/$_dirname

	[ ! -d "$_full_path" ] && mkdir -p $_full_path
	cd $_full_path
	isin_git=$(git rev-parse --is-inside-work-tree 2>/dev/null )
	if [ "$isin_git" == "true" ];then
		_verify_remote $_full_path $remote_origin $_origin_url
		_verify_remote $_full_path $remote_sync $_sync_url
	else
		[ $(ls -A $_full_path) ] && { print_msg  "$_full_path is not empty.  Aborting";exit 1; }
		cd $_full_path
		git clone $_origin_url .
		git remote add $remote_sync $_sync_url
	fi

	cd $_full_path

	##git fetch origin 'remote_branch':'local_branch_name'
	##This will fetch the remote branch and create a new local branch (if not exists already) with name local_branch_name and track the remote one in it.

	if [ "$(git rev-parse --verify --quiet $_branch)" == "" ];then
		#git checkout -b $_branch
		#git pull $remote_origin $_branch

		#fix conflict between branches
		git fetch $remote_origin "$_branch":"$_branch"
		git checkout $_branch
	fi

	if [ "$(git rev-parse --verify --quiet sync-$_branch)" == ""  ];then
		#git pull $remote_sync $_branch
		#git branch --track sync-$_branch  $remote_sync/$_branch
		
		git checkout $_branch
		git fetch $remote_sync "$_branch":"sync-$_branch"
		git merge sync-$_branch
		
		git push -u $remote_origin $_branch
	fi

	git checkout sync-$_branch
	git pull $remote_sync $_branch

	git checkout $_branch

	if [ "$auto_commit_origin" == "1" ];then
		_git_commit $_full_path
	fi

	if [ "$auto_pull_origin" == "1" ];then
		git pull $remote_origin $_branch
	fi

	if [ "$auto_merge_sync" == "1" ];then
		git merge sync-$_branch
	fi

	if [ "$auto_push_origin" == "1" ];then
		git push $remote_origin $_branch
	fi
}

function _git_commit() {
    ## must be current directory
    local dir=$1

    _yes_commit_mesg="Commited by sync.sh"

    cd ${dir}
    ##
    git_conflicts=$(git ls-files -u | cut -f 2 | sort -u | wc -l | tr -d ' ')
    if [[ "${git_conflicts}" != "0" ]];then
	print_
        echo "Please resolve conflict for:$dir"
        git ls-files -u | cut -f 2 | sort -u
        exit 1
    fi

    git_status=$(git status -s|wc -l)
    if [[ "$git_status" != "0" ]];then
        if [ -f "$dir/.gitmodules" ];then
                tmpname=$(mktemp)
                cat $dir/.gitmodules | awk  -F  "=" '$1 ~ /path/ {print $2}' | tr -d ' ' > $tmpname
                while read line && [ -n "$line" ];
                do
                            echo "Submodule:$line"
                            l=`echo $line | tr -d ' '`
                    [ -d "$dir/$l" ] &&  _git_commit $dir/$l
                done < $tmpname
        fi
        #must cd dir
        cd $dir
        git add .
        git commit -m "${_yes_commit_mesg}"
    fi
}

function _verify_remote(){
	local _fullpath=$1
	local _remote_name=$2
	local _remote_url=$3

	local existed_url
	local existed_remote
	local existed_remote_num

	[ -z $_fullpath ] && { print_msg  "_fullpath is empty"; exit 1; }
	[ -z $_remote_name ] && { print_msg  "_remote_name is empty"; exit 1; }
	[ -z $_remote_url ] && { print_msg  "_remote_url is empty"; exit 1; }

	cd $_fullpath

	local_existed_remote_num=$(git remote | grep $_remote_name | wc -l | tr -d ' ')
	if [ "$local_existed_remote_num" == "1"  ];then
		existed_remote=$(git remote | grep $_remote_name)
		if [ "$existed_remote" == "$_remote_name" ];then
			existed_url=$(git remote get-url $_remote_name)
			[ "$existed_url" != "$_remote_url" ] && exit "$_fullpath existing another repo.  Aborting."
			#print_msg "go next1"
		else
			# not test
			print_msg "so many remotes with same string:$_remote_name,Please change directory of $sync_json"
			exit 1
		fi
	else
		# not test
		if [ "$local_existed_remote_num" == "0" ];then
			git remote add $_remote_name $_remote_url
			#print_msg "go next2"
		else
			print_msg "so many remotes with same string:$_remote_name,Please change directory of $sync_json"
			exit 1
		fi
	fi
}

function guess_sync_json(){
	if [[ "$sync_json" =~ ^\/.*  ]];then
		echo
	else
		sync_json=$PWD/$sync_json
	fi
	#print_msg "guess fullpath:$sync_json"
	[ -f "$sync_json" ] || { print_msg  "$sync_json not exist!  Aborting.";exit 1; }
}

function run(){
	guess_sync_json
	check_remotes
	check_directory
	pull_sync
}

function check_autoargs(){

	if [ "$auto_push_origin" == "1" ];then
		auto_merge_sync=1
	fi
	if [ "$auto_merge_sync" == "1" ];then
		auto_pull_origin=1
	fi
	if [ "$auto_pull_origin" == "1" ];then
		auto_commit_origin=1
	fi
}

######------------------------#########

O=`getopt -o f:c:l:m:p: --long syn-json:,auto-commit-origin,auto-pull-origin,auto-merge-sync,auto-push-origin -- "$@"` || exit 1
eval set -- "$O"
# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -f|--sync-json)
            case "$2" in
                "") shift 2 ;;
                *) sync_json=$2 ; shift 2 ;;
            esac ;;
        -c|--auto-commit-origin)
            case "$2" in
                "") shift 2 ;;
                *) auto_commit_origin=$2 ; shift 2 ;;
            esac ;;
        -l|--auto-pull-origin)
            case "$2" in
                "") shift 2 ;;
                *) auto_pull_origin=$2 ; shift 2 ;;
            esac ;;
        -m|--auto-merge-sync)
            case "$2" in
                "") shift 2 ;;
                *) auto_merge_sync=$2 ; shift 2 ;;
            esac ;;
        -p|--auto-push-origin)
            case "$2" in
                "") shift 2 ;;
                *) auto_push_origin=$2 ; shift 2 ;;
            esac ;;
        --) shift ; break ;;
        *) print_msg "Internal error!" ; exit 1 ;;
    esac
done

######------------------------#########
check_autoargs
check_require
run
