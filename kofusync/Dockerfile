# Compila el servidor a un ejecutable nativo y lo copia a una imagen mínima.
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml ./
RUN dart pub get
COPY bin ./bin
RUN dart compile exe bin/server.dart -o /app/kofusync

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/kofusync /app/kofusync
ENV KOFUSYNC_DATA=/data KOFUSYNC_PORT=8080
EXPOSE 8080
CMD ["/app/kofusync"]
