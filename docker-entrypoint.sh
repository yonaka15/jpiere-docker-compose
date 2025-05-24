#!/usr/bin/env bash

set -Eeo pipefail

echo "JPiere Docker - iDempiere日本商習慣対応版"
cat $IDEMPIERE_HOME/MD5SUMS

# 環境変数設定
JAVA_OPTIONS=${JAVA_OPTIONS:-""}
KEY_STORE_PASS=${KEY_STORE_PASS:-myPassword}
KEY_STORE_ON=${KEY_STORE_ON:-idempiere.org}
KEY_STORE_OU=${KEY_STORE_OU:-"JPiere Docker"}
KEY_STORE_O=${KEY_STORE_O:-JPiere}
KEY_STORE_L=${KEY_STORE_L:-myTown}
KEY_STORE_S=${KEY_STORE_S:-CA}
KEY_STORE_C=${KEY_STORE_C:-US}
HOST=${HOST:-0.0.0.0}
IDEMPIERE_PORT=${IDEMPIERE_PORT:-8080}
IDEMPIERE_SSL_PORT=${IDEMPIERE_SSL_PORT:-8443}
TELNET_PORT=${TELNET_PORT:-12612}
DB_HOST=${DB_HOST:-postgres}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-idempiere}
DB_USER=${DB_USER:-adempiere}
DB_PASS=${DB_PASS:-adempiere}
DB_ADMIN_USER=${DB_ADMIN_USER:-postgres} # <<< 修正点: DB_ADMIN_USER の定義を追加
DB_ADMIN_PASS=${DB_ADMIN_PASS:-postgres}
MAIL_HOST=${MAIL_HOST:-0.0.0.0}
MAIL_USER=${MAIL_USER:-info}
MAIL_PASS=${MAIL_PASS:-info}
MAIL_ADMIN=${MAIL_ADMIN:-info@idempiere}
MIGRATE_EXISTING_DATABASE=${MIGRATE_EXISTING_DATABASE:-false}
DISABLE_SSL=${DISABLE_SSL:-false}

# パスワードファイル対応
if [[ -n "$DB_PASS_FILE" ]]; then
    echo "DB_PASS_FILE set as $DB_PASS_FILE..."
    DB_PASS=$(cat $DB_PASS_FILE)
fi

if [[ -n "$DB_ADMIN_PASS_FILE" ]]; then
    echo "DB_ADMIN_PASS_FILE set as $DB_ADMIN_PASS_FILE..."
    DB_ADMIN_PASS=$(cat $DB_ADMIN_PASS_FILE)
fi

if [[ -n "$MAIL_PASS_FILE" ]]; then
    echo "MAIL_PASS_FILE set as $MAIL_PASS_FILE..."
    MAIL_PASS=$(cat $MAIL_PASS_FILE)
fi

if [[ -n "$KEY_STORE_PASS_FILE" ]]; then
    echo "KEY_STORE_PASS_FILE set as $KEY_STORE_PASS_FILE..."
    KEY_STORE_PASS=$(cat $KEY_STORE_PASS_FILE)
fi

# Docker向けJetty設定ファイル処理関数
setup_jetty_config() {
    echo "=== Setting up Jetty configuration files ==="
    
    local jetty_etc_dir="$IDEMPIERE_HOME/jettyhome/etc"
    local template_dir="$IDEMPIERE_HOME/org.adempiere.server-feature/jettyhome/etc"
    
    # テンプレートディレクトリが存在しない場合は、現在のディレクトリをテンプレートとして使用
    if [[ ! -d "$template_dir" ]]; then
        template_dir="$jetty_etc_dir"
    fi
    
    echo "Template directory: $template_dir"
    echo "Target directory: $jetty_etc_dir"
    
    # jettyhome/etcディレクトリが存在しない場合に作成
    mkdir -p "$jetty_etc_dir"
    
    # テンプレートファイルの処理
    for template_file in "$template_dir"/*-template.xml; do
        if [[ -f "$template_file" ]]; then
            local basename=$(basename "$template_file")
            local target_file="$jetty_etc_dir/${basename/-template/}"
            
            echo "Processing template: $basename -> $(basename "$target_file")"
            
            # プレースホルダーの置換（区切り文字を|に変更）
            sed -e "s|@ADEMPIERE_SSL_PORT@|$IDEMPIERE_SSL_PORT|g" \
                -e "s|@ADEMPIERE_PORT@|$IDEMPIERE_PORT|g" \
                -e "s|@ADEMPIERE_WEB_PORT@|$IDEMPIERE_PORT|g" \
                -e "s|@ADEMPIERE_WEB_SSL_PORT@|$IDEMPIERE_SSL_PORT|g" \
                -e "s|@ADEMPIERE_HOST@|$HOST|g" \
                -e "s|@ADEMPIERE_KEYSTORE@|$jetty_etc_dir/keystore|g" \
                -e "s|@ADEMPIERE_KEYSTOREPASS@|$KEY_STORE_PASS|g" \
                -e "s|@ADEMPIERE_KEYPASS@|$KEY_STORE_PASS|g" \
                "$template_file" > "$target_file"
            
            echo "✓ Created $target_file"
        fi
    done
    
    # 必要最小限のjetty.xmlが存在しない場合に作成
    if [[ ! -f "$jetty_etc_dir/jetty.xml" ]]; then
        echo "Creating basic jetty.xml..."
        cat > "$jetty_etc_dir/jetty.xml" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE Configure PUBLIC "-//Jetty//Configure//EN" "https://www.eclipse.org/jetty/configure_10_0.dtd">

<Configure id="Server" class="org.eclipse.jetty.server.Server">
    <Arg name="threadpool"><Ref refid="threadPool"/></Arg>

    <Call name="addBean">
      <Arg><Ref refid="byteBufferPool"/></Arg>
    </Call>

    <Call name="addBean">
      <Arg>
        <New class="org.eclipse.jetty.util.thread.ScheduledExecutorScheduler">
          <Arg name="name"><Property name="jetty.scheduler.name"/></Arg>
          <Arg name="daemon" type="boolean"><Property name="jetty.scheduler.daemon" default="false" /></Arg>
          <Arg name="threads" type="int"><Property name="jetty.scheduler.threads" default="-1" /></Arg>
        </New>
      </Arg>
    </Call>

    <New id="httpConfig" class="org.eclipse.jetty.server.HttpConfiguration">
      <Set name="secureScheme">https</Set>
      <Set name="securePort">8443</Set>
      <Set name="outputBufferSize">32768</Set>
      <Set name="outputAggregationSize">8192</Set>
      <Set name="requestHeaderSize">8192</Set>
      <Set name="responseHeaderSize">8192</Set>
      <Set name="sendServerVersion">true</Set>
      <Set name="sendDateHeader">false</Set>
      <Set name="headerCacheSize">1024</Set>
      <Set name="delayDispatchUntilContent">true</Set>
      <Set name="maxErrorDispatches">10</Set>
      <Set name="persistentConnectionsEnabled">true</Set>
      <Set name="httpCompliance"><Call class="org.eclipse.jetty.http.HttpCompliance" name="from"><Arg>RFC7230</Arg></Call></Set>
      <Set name="requestCookieCompliance"><Call class="org.eclipse.jetty.http.CookieCompliance" name="valueOf"><Arg>RFC6265</Arg></Call></Set>
      <Set name="responseCookieCompliance"><Call class="org.eclipse.jetty.http.CookieCompliance" name="valueOf"><Arg>RFC6265</Arg></Call></Set>
      <Set name="relativeRedirectAllowed">false</Set>
    </New>

    <Set name="handler">
      <New id="Handlers" class="org.eclipse.jetty.server.handler.HandlerCollection">
        <Set name="handlers">
         <Array type="org.eclipse.jetty.server.Handler">
           <Item>
             <New id="Contexts" class="org.eclipse.jetty.server.handler.ContextHandlerCollection"/>
           </Item>
           <Item>
             <New id="DefaultHandler" class="org.eclipse.jetty.server.handler.DefaultHandler"/>
           </Item>
         </Array>
        </Set>
      </New>
    </Set>

    <Set name="stopAtShutdown">true</Set>
    <Set name="stopTimeout">5000</Set>
    <Set name="dumpAfterStart">false</Set>
    <Set name="dumpBeforeStop">false</Set>

    <Set class="org.eclipse.jetty.util.resource.Resource" name="defaultUseCaches">false</Set>

    <Call class="org.eclipse.jetty.webapp.Configurations" name="setServerDefault">
        <Arg>
            <Ref refid="Server"/>
        </Arg>
        <Call name="add">
            <Arg name="configClass">
                <Array type="String">
                    <Item>org.eclipse.jetty.webapp.FragmentConfiguration</Item>
                    <Item>org.eclipse.jetty.webapp.JettyWebXmlConfiguration</Item>
                    <Item>org.eclipse.jetty.webapp.WebXmlConfiguration</Item>
                    <Item>org.eclipse.jetty.webapp.WebAppConfiguration</Item>
                    <Item>org.eclipse.jetty.webapp.ServletsConfiguration</Item>
                    <Item>org.eclipse.jetty.webapp.JspConfiguration</Item>
                    <Item>org.eclipse.jetty.webapp.JaasConfiguration</Item>
                    <Item>org.eclipse.jetty.webapp.JndiConfiguration</Item>
                    <Item>org.eclipse.jetty.plus.webapp.PlusConfiguration</Item>
                    <Item>org.eclipse.jetty.plus.webapp.EnvConfiguration</Item>
                    <Item>org.eclipse.jetty.webapp.JmxConfiguration</Item>
                    <Item>org.eclipse.jetty.osgi.annotations.AnnotationConfiguration</Item>
                    <Item>org.eclipse.jetty.websocket.server.config.JettyWebSocketConfiguration</Item>
                    <Item>org.eclipse.jetty.websocket.javax.server.config.JavaxWebSocketConfiguration</Item>
                    <Item>org.eclipse.jetty.osgi.boot.OSGiWebInfConfiguration</Item>
                    <Item>org.eclipse.jetty.osgi.boot.OSGiMetaInfConfiguration</Item>
                </Array>
            </Arg>
        </Call>
    </Call>

    <Call class="java.lang.System" name="setProperty">
      <Arg>java.naming.factory.initial</Arg>
      <Arg>org.eclipse.jetty.jndi.InitialContextFactory</Arg>
    </Call>
    <Call class="java.lang.System" name="setProperty">
      <Arg>java.naming.factory.url.pkgs</Arg>
      <Arg>org.eclipse.jetty.jndi</Arg>
    </Call>
</Configure>
EOF'''
        echo "✓ Created basic jetty.xml"
    fi
    
    echo "Final Jetty configuration files:"
    ls -la "$jetty_etc_dir"/*.xml 2>/dev/null || echo "(No XML files found)"
    
    # 全設定ファイルで残っているプレースホルダーを最終チェック・修正
    echo "=== Final placeholder check and cleanup ==="
    local files_with_placeholders=0
    for config_file in "$jetty_etc_dir"/*.xml; do
        if [[ -f "$config_file" ]] && grep -q "@.*@" "$config_file"; then
            echo "Found remaining placeholders in $(basename "$config_file"), fixing..."
            sed -i -e "s|@ADEMPIERE_APPS_SERVER@|$HOST|g" \
                   -e "s|@ADEMPIERE_SSL_PORT@|$IDEMPIERE_SSL_PORT|g" \
                   -e "s|@ADEMPIERE_PORT@|$IDEMPIERE_PORT|g" \
                   -e "s|@ADEMPIERE_WEB_PORT@|$IDEMPIERE_PORT|g" \
                   -e "s|@ADEMPIERE_WEB_SSL_PORT@|$IDEMPIERE_SSL_PORT|g" \
                   -e "s|@ADEMPIERE_HOST@|$HOST|g" \
                   -e "s|@ADEMPIERE_KEYSTORE@|$jetty_etc_dir/keystore|g" \
                   -e "s|@ADEMPIERE_KEYSTOREPASS@|$KEY_STORE_PASS|g" \
                   -e "s|@ADEMPIERE_KEYPASS@|$KEY_STORE_PASS|g" \
                   "$config_file"
            files_with_placeholders=$((files_with_placeholders + 1))
        fi
    done
    
    if [[ $files_with_placeholders -gt 0 ]]; then
        echo "✓ Fixed placeholders in $files_with_placeholders files"
    else
        echo "✓ No remaining placeholders found"
    fi
    
    # SSL設定の無効化（オプション）
    if [[ "${DISABLE_SSL:-false}" == "true" ]]; then
        echo "=== Disabling SSL configuration (DISABLE_SSL=true) ==="
        
        # SSL設定ファイルを無効化する代わりに、最小限の設定ファイルを作成
        # （Jettyの設定リストにこれらのファイルがハードコードされているため）
        
        if [[ -f "$jetty_etc_dir/jetty-ssl.xml" ]]; then
            echo "Creating minimal jetty-ssl.xml (SSL disabled)..."
            cat > "$jetty_etc_dir/jetty-ssl.xml" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE Configure PUBLIC "-//Jetty//Configure//EN" "https://www.eclipse.org/jetty/configure_10_0.dtd">
<!-- SSL disabled configuration -->
<Configure id="sslContextFactory" class="org.eclipse.jetty.util.ssl.SslContextFactory$Server">
  <Set name="Provider"><Property name="jetty.sslContext.provider"/></Set>
</Configure>
EOF'''
            echo "✓ Created minimal jetty-ssl.xml"
        fi
        
        if [[ -f "$jetty_etc_dir/jetty-ssl-context.xml" ]]; then
            echo "Creating minimal jetty-ssl-context.xml (SSL disabled)..."
            cat > "$jetty_etc_dir/jetty-ssl-context.xml" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE Configure PUBLIC "-//Jetty//Configure//EN" "https://www.eclipse.org/jetty/configure_10_0.dtd">
<!-- SSL context disabled configuration -->
<Configure id="sslContextFactory" class="org.eclipse.jetty.util.ssl.SslContextFactory$Server">
  <!-- SSL disabled -->
</Configure>
EOF'''
            echo "✓ Created minimal jetty-ssl-context.xml"
        fi
        
        if [[ -f "$jetty_etc_dir/jetty-https.xml" || -f "$jetty_etc_dir/jetty-https.xml.disabled" ]]; then
    echo "Creating minimal jetty-https.xml (SSL disabled)..."
    cat > "$jetty_etc_dir/jetty-https.xml" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE Configure PUBLIC "-//Jetty//Configure//EN" "https://www.eclipse.org/jetty/configure_10_0.dtd">
<!-- HTTPS connector disabled as DISABLE_SSL=true -->
<Configure id="Server" class="org.eclipse.jetty.server.Server">
</Configure>
EOF'''
    echo "✓ Created minimal jetty-https.xml for disabled SSL"
    # もし jetty-https.xml.disabled が存在すれば削除
    rm -f "$jetty_etc_dir/jetty-https.xml.disabled"
fi
        
        echo "SSL configurations set to minimal (HTTP only mode on port $IDEMPIERE_PORT)"
    fi
    
    echo "=== Jetty configuration setup completed ==="
}

if [[ "$1" == "idempiere" ]]; then
    # PostgreSQL接続待機
    RETRIES=30
    until PGPASSWORD=$DB_ADMIN_PASS psql -h $DB_HOST -U "$DB_ADMIN_USER" -c "\q" > /dev/null 2>&1 || [[ $RETRIES == 0 ]]; do # <<< 修正点
        echo "Waiting for postgres server, $((RETRIES--)) remaining attempts..."
        sleep 1
    done

    if [[ $RETRIES == 0 ]]; then
        echo "PostgreSQL connection failed. Shutting down..."
        exit 1
    fi

    echo "PostgreSQL connection successful!"

    # デフォルト設定削除（Docker環境向け）
    echo "Removing default settings..."
    rm -f idempiereEnv.properties jettyhome/etc/keystore

    # Jetty設定ファイルの事前処理
    setup_jetty_config

    # コンソールセットアップ実行
    echo "Executing console-setup..."
    # 注意: console-setup.sh に DB_ADMIN_USER を渡す必要があれば、ここの入力文字列を修正する必要がある
    echo -e "$JAVA_HOME\n$JAVA_OPTIONS\n$IDEMPIERE_HOME\n$KEY_STORE_PASS\n$KEY_STORE_ON\n$KEY_STORE_OU\n$KEY_STORE_O\n$KEY_STORE_L\n$KEY_STORE_S\n$KEY_STORE_C\n$HOST\n$IDEMPIERE_PORT\n$IDEMPIERE_SSL_PORT\nN\n2\n$DB_HOST\n$DB_PORT\n$DB_NAME\n$DB_USER\n$DB_PASS\n$DB_ADMIN_PASS\n$MAIL_HOST\n$MAIL_USER\n$MAIL_PASS\n$MAIL_ADMIN\nY\n" | ./console-setup.sh

    # コンソールセットアップ後のJetty設定再処理（念のため）
    setup_jetty_config

    # データベース初期化チェック
    if ! PGPASSWORD=$DB_PASS psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "\q" > /dev/null 2>&1 ; then
        echo "Database '$DB_NAME' not found or user '$DB_USER' doesn't exist, initializing..."
        
        # PostgreSQLユーザーが存在しない場合は作成
        echo "Creating PostgreSQL user '$DB_USER' if not exists..."
        PGPASSWORD=$DB_ADMIN_PASS psql -h $DB_HOST -U "$DB_ADMIN_USER" -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || echo "User $DB_USER already exists" # <<< 修正点
        PGPASSWORD=$DB_ADMIN_PASS psql -h $DB_HOST -U "$DB_ADMIN_USER" -c "ALTER USER $DB_USER CREATEDB;" 2>/dev/null || echo "User $DB_USER already has CREATEDB privilege" # <<< 修正点
        
        # データベースが存在しない場合は作成
        echo "Creating database '$DB_NAME' if not exists..."
        PGPASSWORD=$DB_ADMIN_PASS psql -h $DB_HOST -U "$DB_ADMIN_USER" -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || echo "Database $DB_NAME already exists" # <<< 修正点
        
        # JPiere固有: ExpDat.dmpでデータベース初期化
        echo "Importing JPiere database from ExpDat.dmp..."
        PGPASSWORD=$DB_ADMIN_PASS psql -h $DB_HOST -U "$DB_ADMIN_USER" -d $DB_NAME -f /tmp/ExpDat.dmp # <<< 修正点
        echo "JPiere database import completed"
        
        # データベース権限設定
        echo "Setting database permissions..."
        PGPASSWORD=$DB_ADMIN_PASS psql -h $DB_HOST -U "$DB_ADMIN_USER" -d $DB_NAME -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" # <<< 修正点
        PGPASSWORD=$DB_ADMIN_PASS psql -h $DB_HOST -U "$DB_ADMIN_USER" -d $DB_NAME -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;" # <<< 修正点
        PGPASSWORD=$DB_ADMIN_PASS psql -h $DB_HOST -U "$DB_ADMIN_USER" -d $DB_NAME -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;" # <<< 修正点
        
        # データベース同期
        cd utils
        echo "Synchronizing database..."
        ./RUN_SyncDB.sh
        cd ..
        
        # データベース署名
        echo "Signing database..."
        ./sign-database-build.sh
    else
        echo "Database '$DB_NAME' already exists and user '$DB_USER' can connect..."
        if [[ "$MIGRATE_EXISTING_DATABASE" == "true" ]]; then
            cd utils
            echo "MIGRATE_EXISTING_DATABASE is true. Synchronizing database..."
            ./RUN_SyncDB.sh
            cd ..
            echo "Signing database..."
            ./sign-database-build.sh
        else
            echo "MIGRATE_EXISTING_DATABASE is false. Skipping migration..."
        fi
    fi
fi

exec "$@"
