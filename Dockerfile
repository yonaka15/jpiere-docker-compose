FROM --platform=linux/amd64 eclipse-temurin:17-jdk-jammy

LABEL maintainer="jpiere-docker"

ENV IDEMPIERE_VERSION 11
ENV IDEMPIERE_HOME /opt/idempiere
ENV IDEMPIERE_PLUGINS_HOME $IDEMPIERE_HOME/plugins
ENV IDEMPIERE_LOGS_HOME $IDEMPIERE_HOME/log

WORKDIR $IDEMPIERE_HOME

# 必要なパッケージのインストール
RUN apt-get update && \
  apt-get install -y --no-install-recommends nano postgresql-client unzip && \
  rm -rf /var/lib/apt/lists/*

# ローカルファイルをコンテナにコピー
# https://sourceforge.net/projects/jpiere/files/JPiere-latest/
COPY files/JPiereServer11.gtk.linux.x86_64.zip /tmp/jpiere-server.zip
COPY files/ExpDat.jar /tmp/ExpDat.jar

# JPiereサーバーのセットアップ
RUN echo "=== JPiere Server Setup Start ===" && \
  echo "Hash: $(md5sum /tmp/jpiere-server.zip)" > $IDEMPIERE_HOME/MD5SUMS && \
  echo "Date: $(date)" >> $IDEMPIERE_HOME/MD5SUMS && \
  echo "=== Extracting JPiere Server ===" && \
  cd /tmp && \
  unzip -q jpiere-server.zip && \
  echo "=== Post-extraction directory listing ===" && \
  ls -la /tmp/ && \
  echo "=== Finding jpiere-server directory ===" && \
  JPIERE_DIR=$(find /tmp -maxdepth 1 -name "jpiere-server*" -type d | head -1) && \
  echo "Found JPiere directory: $JPIERE_DIR" && \
  if [ -n "$JPIERE_DIR" ] && [ -d "$JPIERE_DIR" ]; then \
  echo "=== Content of jpiere-server directory ===" && \
  ls -la "$JPIERE_DIR"/ && \
  echo "=== Copying files to $IDEMPIERE_HOME ===" && \
  cp -r "$JPIERE_DIR"/* "$IDEMPIERE_HOME"/ && \
  echo "=== Cleanup temporary files ===" && \
  rm -rf "$JPIERE_DIR" && \
  rm -f /tmp/jpiere-server.zip && \
  echo "=== JPiere Server Setup Completed ===" && \
  ls -la "$IDEMPIERE_HOME"; \
  else \
  echo "ERROR: JPiere server directory not found!" && \
  exit 1; \
  fi

# ExpDat.jarの解凍（JPiere用PostgreSQLダンプファイル）
RUN echo "=== ExpDat.jar Processing Start ===" && \
  cd /tmp && \
  if [ -f ExpDat.jar ]; then \
  unzip ExpDat.jar && \
  ls -la ExpDat.dmp && \
  echo "ExpDat.dmpファイルを/tmp/に配置完了" && \
  rm ExpDat.jar; \
  else \
  echo "ERROR: ExpDat.jar not found!" && \
  exit 1; \
  fi

# myEnvironment.shの作成と必要ファイルの確認
RUN echo "=== Environment Setup ===" && \
  if [ ! -d "$IDEMPIERE_HOME/utils" ]; then \
  mkdir -p "$IDEMPIERE_HOME/utils"; \
  fi && \
  if [ ! -f "$IDEMPIERE_HOME/utils/myEnvironment.sh" ]; then \
  echo "#!/bin/bash" > "$IDEMPIERE_HOME/utils/myEnvironment.sh" && \
  echo "# Generated myEnvironment.sh for JPiere Docker" >> "$IDEMPIERE_HOME/utils/myEnvironment.sh" && \
  echo "export JAVA_HOME=${JAVA_HOME}" >> "$IDEMPIERE_HOME/utils/myEnvironment.sh" && \
  echo "export IDEMPIERE_HOME=${IDEMPIERE_HOME}" >> "$IDEMPIERE_HOME/utils/myEnvironment.sh" && \
  echo "export PATH=\$PATH:\$JAVA_HOME/bin" >> "$IDEMPIERE_HOME/utils/myEnvironment.sh" && \
  chmod +x "$IDEMPIERE_HOME/utils/myEnvironment.sh" && \
  echo "Created myEnvironment.sh"; \
  fi

# ファイル構造の最終確認
RUN echo "=== Final Directory Structure Check ===" && \
  echo "iDempiere Home Directory:" && \
  ls -la $IDEMPIERE_HOME && \
  echo "" && \
  echo "Utils Directory:" && \
  ls -la $IDEMPIERE_HOME/utils/ && \
  echo "" && \
  echo "Jetty Template Directory:" && \
  find $IDEMPIERE_HOME -name "*template*.xml" -type f && \
  echo "" && \
  echo "Checking for key files:" && \
  [ -f "$IDEMPIERE_HOME/idempiere-server.sh" ] && echo "✓ idempiere-server.sh found" || echo "✗ idempiere-server.sh missing" && \
  [ -f "$IDEMPIERE_HOME/utils/myEnvironment.sh" ] && echo "✓ myEnvironment.sh found" || echo "✗ myEnvironment.sh missing" && \
  [ -f "$IDEMPIERE_HOME/console-setup.sh" ] && echo "✓ console-setup.sh found" || echo "✗ console-setup.sh missing"

# MD5SUMSファイルの表示
RUN echo "=== Build Information ===" && \
  cat $IDEMPIERE_HOME/MD5SUMS

# シンボリックリンクの作成
RUN if [ -f "$IDEMPIERE_HOME/idempiere-server.sh" ]; then \
  ln -s "$IDEMPIERE_HOME/idempiere-server.sh" /usr/bin/idempiere && \
  echo "Created symlink for idempiere-server.sh"; \
  else \
  echo "WARNING: idempiere-server.sh not found, creating placeholder" && \
  echo '#!/bin/bash' > /usr/bin/idempiere && \
  echo 'echo "iDempiere server - idempiere-server.sh not found"' >> /usr/bin/idempiere && \
  echo 'echo "Available files in $IDEMPIERE_HOME:"' >> /usr/bin/idempiere && \
  echo 'ls -la $IDEMPIERE_HOME' >> /usr/bin/idempiere && \
  chmod +x /usr/bin/idempiere; \
  fi

# エントリーポイントスクリプトをコピー
COPY docker-entrypoint.sh $IDEMPIERE_HOME/docker-entrypoint.sh
RUN chmod +x $IDEMPIERE_HOME/docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["idempiere"]
