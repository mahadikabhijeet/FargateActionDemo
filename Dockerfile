FROM debian:jessie-backports

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
#RUN groupadd -r www-data && useradd -r --create-home -g www-data www-data

ENV HTTPD_PREFIX /usr/local/apache2
ENV PATH $HTTPD_PREFIX/bin:$PATH
RUN mkdir -p "$HTTPD_PREFIX" \
	&& chown www-data:www-data "$HTTPD_PREFIX"
WORKDIR $HTTPD_PREFIX

# library for mod_http2
ENV NGHTTP2_VERSION 1.18.1-1
ENV OPENSSL_VERSION 1.0.2l-1~bpo8+1
RUN { \
		echo 'deb http://deb.debian.org/debian stretch main'; \
	} > /etc/apt/sources.list.d/stretch.list \
	&& { \
# add a negative "Pin-Priority" so that we never ever get packages from stretch unless we explicitly request them
		echo 'Package: *'; \
		echo 'Pin: release n=stretch'; \
		echo 'Pin-Priority: -10'; \
		echo; \
# except nghttp2, which is the reason we're here
		echo 'Package: libnghttp2*'; \
		echo "Pin: version $NGHTTP2_VERSION"; \
		echo 'Pin-Priority: 990'; \
		echo; \
	} > /etc/apt/preferences.d/unstable-nghttp2

# install httpd runtime dependencies
# https://httpd.apache.org/docs/2.4/install.html#requirements
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		libapr1 \
		libaprutil1 \
		libaprutil1-ldap \
		libapr1-dev \
		libaprutil1-dev \
		liblua5.2-0 \
		libnghttp2-14=$NGHTTP2_VERSION \
		libpcre++0 \
		libssl1.0.0=$OPENSSL_VERSION \
		libxml2 \
	&& rm -r /var/lib/apt/lists/*

ENV HTTPD_VERSION 2.4.27
ENV HTTPD_SHA1 699e4e917e8fb5fd7d0ce7e009f8256ed02ec6fc

# https://issues.apache.org/jira/browse/INFRA-8753?focusedCommentId=14735394#comment-14735394
ENV HTTPD_BZ2_URL https://www.apache.org/dyn/closer.cgi?action=download&filename=httpd/httpd-$HTTPD_VERSION.tar.bz2
# not all the mirrors actually carry the .asc files :'(
ENV HTTPD_ASC_URL https://www.apache.org/dist/httpd/httpd-$HTTPD_VERSION.tar.bz2.asc

# if the version is outdated, we have to pull from the archive :/
ENV HTTPD_BZ2_FALLBACK_URL https://archive.apache.org/dist/httpd/httpd-$HTTPD_VERSION.tar.bz2
ENV HTTPD_ASC_FALLBACK_URL https://archive.apache.org/dist/httpd/httpd-$HTTPD_VERSION.tar.bz2.asc

# see https://httpd.apache.org/docs/2.4/install.html#requirements
RUN set -x \
	# mod_http2 mod_lua mod_proxy_html mod_xml2enc
	# https://anonscm.debian.org/cgit/pkg-apache/apache2.git/tree/debian/control?id=adb6f181257af28ee67af15fc49d2699a0080d4c
	&& buildDeps=" \
		bzip2 \
		ca-certificates \
		dpkg-dev \
		gcc \
		liblua5.2-dev \
		libnghttp2-dev=$NGHTTP2_VERSION \
		libpcre++-dev \
		libssl-dev=$OPENSSL_VERSION \
		libxml2-dev \
		zlib1g-dev \
		make \
		wget \
	" \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends -V $buildDeps \
	&& rm -r /var/lib/apt/lists/* \
	\
	&& { \
		wget -O httpd.tar.bz2 "$HTTPD_BZ2_URL" \
		|| wget -O httpd.tar.bz2 "$HTTPD_BZ2_FALLBACK_URL" \
	; } \
	&& echo "$HTTPD_SHA1 *httpd.tar.bz2" | sha1sum -c - \
# see https://httpd.apache.org/download.cgi#verify
	&& { \
		wget -O httpd.tar.bz2.asc "$HTTPD_ASC_URL" \
		|| wget -O httpd.tar.bz2.asc "$HTTPD_ASC_FALLBACK_URL" \
	; } \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys A93D62ECC3C8EA12DB220EC934EA76E6791485A8 \
	&& gpg --batch --verify httpd.tar.bz2.asc httpd.tar.bz2 \
	&& rm -rf "$GNUPGHOME" httpd.tar.bz2.asc \
	\
	&& mkdir -p src \
	&& tar -xf httpd.tar.bz2 -C src --strip-components=1 \
	&& rm httpd.tar.bz2 \
	&& cd src \
	\
	&& gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
	&& ./configure \
		--build="$gnuArch" \
		--prefix="$HTTPD_PREFIX" \
		--enable-mods-shared=reallyall \
	&& make -j "$(nproc)" \
	&& make install \
	\
	&& cd .. \
	&& rm -r src man manual \
	\
	&& sed -ri \
		-e 's!^(\s*CustomLog)\s+\S+!\1 /proc/self/fd/1!g' \
		-e 's!^(\s*ErrorLog)\s+\S+!\1 /proc/self/fd/2!g' \
		"$HTTPD_PREFIX/conf/httpd.conf" \
	\
	&& apt-get purge -y --auto-remove $buildDeps

COPY httpd-foreground /usr/local/bin/

EXPOSE 80
CMD ["httpd-foreground"]
