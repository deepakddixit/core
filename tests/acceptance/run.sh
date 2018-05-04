#!/usr/bin/env bash

# composer install

# from http://stackoverflow.com/a/630387
SCRIPT_PATH="`dirname \"$0\"`"              # relative
SCRIPT_PATH="`( cd \"$SCRIPT_PATH\" && pwd )`"  # absolutized and normalized

echo 'Script path: '$SCRIPT_PATH

OC_PATH=$SCRIPT_PATH/../../
OCC=${OC_PATH}occ
BEHAT=${OC_PATH}lib/composer/behat/behat/bin/behat

BEHAT_FEATURE=$1
HIDE_OC_LOGS=$2

# save the current language and set the language to "C"
# we want to have it all in english to be able to parse outputs
OLD_LANG=$LANG
export LANG=C

# Provide a default admin password, but let the caller pass it if they wish
if [ -z "$ADMIN_PASSWORD" ]
then
	ADMIN_PASSWORD="admin"
fi

# @param $1 admin password
# @param $2 occ url
# @param $3 command
# sets $REMOTE_OCC_STDOUT and $REMOTE_OCC_STDERR from returned xml data
# @return occ return code given in the xml data
remote_occ() {
	RESULT=`curl -s -u admin:$1 $2 -d "command=$3"`
	RETURN=`echo $RESULT | xmllint --xpath "string(ocs/data/code)" - | sed 's/ //g'`
	# we could not find a proper return of the testing app, so something went wrong
	if [ -z "$RETURN" ]
	then
		RETURN=1
		REMOTE_OCC_STDERR=$RESULT
	else
		REMOTE_OCC_STDOUT=`echo $RESULT | xmllint --xpath "string(ocs/data/stdOut)" - | sed 's/ //g'`
		REMOTE_OCC_STDERR=`echo $RESULT | xmllint --xpath "string(ocs/data/stdErr)" - | sed 's/ //g'`
	fi
	return $RETURN
}

function env_alt_home_enable {
	$OCC config:app:set testing enable_alt_user_backend --value yes
}

function env_alt_home_clear {
	$OCC app:disable testing || { echo "Unable to disable testing app" >&2; exit 1; }
}

function env_encryption_enable {
	$OCC app:enable encryption
	$OCC encryption:enable
}

function env_encryption_enable_master_key {
	env_encryption_enable || { echo "Unable to enable masterkey encryption" >&2; exit 1; }
	$OCC encryption:select-encryption-type masterkey --yes
}

function env_encryption_enable_user_keys {
	env_encryption_enable || { echo "Unable to enable user-keys encryption" >&2; exit 1; }
	$OCC encryption:select-encryption-type user-keys --yes
}

function env_encryption_disable {
	$OCC encryption:disable
	$OCC app:disable encryption
}

function env_encryption_disable_master_key {
	env_encryption_disable || { echo "Unable to disable masterkey encryption" >&2; exit 1; }
	$OCC config:app:delete encryption useMasterKey
}

function env_encryption_disable_user_keys {
	env_encryption_disable || { echo "Unable to disable user-keys encryption" >&2; exit 1; }
	$OCC config:app:delete encryption userSpecificKey
}

declare -x TEST_SERVER_URL
declare -x TEST_SERVER_FED_URL
declare -x TEST_WITH_PHPDEVSERVER
[[ -z "${TEST_SERVER_URL}" || -z "${TEST_SERVER_FED_URL}" ]] && TEST_WITH_PHPDEVSERVER="true"

if [ "${TEST_WITH_PHPDEVSERVER}" != "true" ]
then
    echo "Not using php inbuilt server for running scenario ..."
    echo "Updating .htaccess for proper rewrites"
    $OCC config:system:set htaccess.RewriteBase --value /
    $OCC maintenance:update:htaccess
else
    echo "Using php inbuilt server for running scenario ..."

    # avoid port collision on jenkins - use $EXECUTOR_NUMBER
    declare -x EXECUTOR_NUMBER
    [[ -z "$EXECUTOR_NUMBER" ]] && EXECUTOR_NUMBER=0

    PORT=$((8080 + $EXECUTOR_NUMBER))
    echo $PORT
    php -S localhost:$PORT -t "$OC_PATH" &
    PHPPID=$!
    echo $PHPPID

    PORT_FED=$((8180 + $EXECUTOR_NUMBER))
    echo $PORT_FED
    php -S localhost:$PORT_FED -t ../.. &
    PHPPID_FED=$!
    echo $PHPPID_FED

    export TEST_SERVER_URL="http://localhost:$PORT"
    export TEST_SERVER_FED_URL="http://localhost:$PORT_FED"

    # Give time for the PHP dev server to become available
    # because we want to use it to get and change settings with the testing app
    sleep 5
fi

# If a feature file has been specified but no suite, then deduce the suite
if [ -n "$BEHAT_FEATURE" ] && [ -z "$BEHAT_SUITE" ]
then
    FEATURE_PATH=`dirname $BEHAT_FEATURE`
    BEHAT_SUITE=`basename $FEATURE_PATH`
fi

if [ "$BEHAT_SUITE" ]
then
	BEHAT_SUITE_OPTION="--suite=$BEHAT_SUITE"
	if [[ $BEHAT_SUITE == api* ]]
	then
	  TEST_TYPE_TAG="@api"
	else
	  TEST_TYPE_TAG="@webUI"
	fi
else
	BEHAT_SUITE_OPTION=""
	# We are running "all" suites in a single run.
	# It is not practical/reasonable to do that with the webUI tests.
	# So just run all the API tests.
	TEST_TYPE_TAG="@api"
fi

# The endpoint to use to do occ commands via the testing app
OCC_URL="$TEST_SERVER_URL/ocs/v2.php/apps/testing/api/v1/occ"

# Set up personalized skeleton
remote_occ $ADMIN_PASSWORD $OCC_URL "--no-warnings config:system:get skeletondirectory"

PREVIOUS_SKELETON_DIR=$REMOTE_OCC_STDOUT

# $SRC_SKELETON_DIR is the path to the skeleton folder on the machine where the tests are executed
# it is used for file comparisons in various tests
if [ "$TEST_TYPE_TAG" == "@api" ]
then
  export SRC_SKELETON_DIR=$(pwd)/skeleton
else
  export SRC_SKELETON_DIR=$(pwd)/webUISkeleton
fi

# $SKELETON_DIR is the path to the skeleton folder on the machine where oC runs (system under test)
# it is used to give users a defined set of files and folders for the tests
if [ -z "$SKELETON_DIR" ]
then
	export SKELETON_DIR="$SRC_SKELETON_DIR"
fi

remote_occ $ADMIN_PASSWORD $OCC_URL "config:system:set skeletondirectory --value=$SKELETON_DIR"

if [ $? -ne 0 ]
then
	echo -e "Could not set skeleton directory. Result:\n'$REMOTE_OCC_STDERR'"
	exit 1
fi

PREVIOUS_HTTP_FALLBACK_SETTING=$($OCC --no-warnings config:system:get sharing.federation.allowHttpFallback)
$OCC config:system:set sharing.federation.allowHttpFallback --type boolean --value true

# Enable external storage app
$OCC config:app:set core enable_external_storage --value=yes
$OCC config:system:set files_external_allow_create_new_local --value=true

PREVIOUS_TESTING_APP_STATUS=$($OCC --no-warnings app:list "^testing$")

if [[ "$PREVIOUS_TESTING_APP_STATUS" =~ ^Disabled: ]]
then
	$OCC app:enable testing || { echo "Unable to enable testing app" >&2; exit 1; }
	TESTING_ENABLED_BY_SCRIPT=true;
else
	TESTING_ENABLED_BY_SCRIPT=false;
fi

mkdir -p work/local_storage || { echo "Unable to create work folder" >&2; exit 1; }
OUTPUT_CREATE_STORAGE=`$OCC files_external:create local_storage local null::null -c datadir=$SCRIPT_PATH/work/local_storage` 

ID_STORAGE=`echo $OUTPUT_CREATE_STORAGE | awk {'print $5'}`

$OCC files_external:option $ID_STORAGE enable_sharing true

if [ "$OC_TEST_ALT_HOME" = "1" ]
then
	env_alt_home_enable
fi

# Enable encryption if requested
if [ "$OC_TEST_ENCRYPTION_ENABLED" = "1" ]
then
	env_encryption_enable
	BEHAT_FILTER_TAGS="~@no_encryption&&~@no_default_encryption"
elif [ "$OC_TEST_ENCRYPTION_MASTER_KEY_ENABLED" = "1" ]
then
	env_encryption_enable_master_key
	BEHAT_FILTER_TAGS="~@no_encryption&&~@no_masterkey_encryption"
elif [ "$OC_TEST_ENCRYPTION_USER_KEYS_ENABLED" = "1" ]
then
	env_encryption_enable_user_keys
	BEHAT_FILTER_TAGS="~@no_encryption&&~@no_userkeys_encryption"
fi

if [ -n "$BEHAT_FILTER_TAGS" ]
then
    if [[ $BEHAT_FILTER_TAGS != *@skip* ]]
    then
    	BEHAT_FILTER_TAGS="$BEHAT_FILTER_TAGS&&~@skip"
   	fi
else
	BEHAT_FILTER_TAGS="~@skip&&~@masterkey_encryption"
fi

BEHAT_FILTER_TAGS="$BEHAT_FILTER_TAGS&&$TEST_TYPE_TAG"

if [ -n "$BEHAT_FILTER_TAGS" ]
then
	BEHAT_PARAMS='{ 
		"gherkin": {
			"filters": {
				"tags": "'"$BEHAT_FILTER_TAGS"'"
			}
		}
	}'
fi

BEHAT_PARAMS="$BEHAT_PARAMS" $BEHAT --strict -f junit -f pretty $BEHAT_SUITE_OPTION $BEHAT_FEATURE
RESULT=$?

$OCC files_external:delete -y $ID_STORAGE

# Disable external storage app
$OCC config:app:set core enable_external_storage --value=no

# Put back state of the testing app
if [ "$TESTING_ENABLED_BY_SCRIPT" = true ]
then
	$OCC app:disable testing
fi

# Put back personalized skeleton
if [ "A$PREVIOUS_SKELETON_DIR" = "A" ]
then
	remote_occ $ADMIN_PASSWORD $OCC_URL "config:system:delete skeletondirectory"
else
	remote_occ $ADMIN_PASSWORD $OCC_URL "config:system:set skeletondirectory --value=$PREVIOUS_SKELETON_DIR"
fi

# Put back HTTP fallback setting
if [ "A$PREVIOUS_HTTP_FALLBACK_SETTING" = "A" ]
then
	$OCC config:system:delete sharing.federation.allowHttpFallback
else
	$OCC config:system:set sharing.federation.allowHttpFallback --type boolean --value="$PREVIOUS_HTTP_FALLBACK_SETTING"
fi

# Clear storage folder
rm -Rf work/local_storage/*

if [ "$OC_TEST_ALT_HOME" = "1" ]
then
	env_alt_home_clear
fi

# Disable encryption if requested
if [ "$OC_TEST_ENCRYPTION_ENABLED" = "1" ]
then
	env_encryption_disable
fi

if [ "$OC_TEST_ENCRYPTION_MASTER_KEY_ENABLED" = "1" ]
then
	env_encryption_disable_master_key
fi

if [ "$OC_TEST_ENCRYPTION_USER_KEYS_ENABLED" = "1" ]
then
	env_encryption_disable_user_keys
fi

if [ "${TEST_WITH_PHPDEVSERVER}" == "true" ]
then
    kill $PHPPID
    kill $PHPPID_FED
fi

if [ -z $HIDE_OC_LOGS ]
then
	tail "${OC_PATH}/data/owncloud.log"
fi

echo "runsh: Exit code: $RESULT"
exit $RESULT
