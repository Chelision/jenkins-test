# jenkins-test-pro

Vue 3 starter project powered by Vite.

## Scripts

```sh
npm install
npm run dev
```

Build for production:

```sh
npm run build
```

Build for COS:

```sh
npm run build:cos
```

## Local and COS deploy

Local development uses local assets by default:

```sh
npm run dev
```

Local builds use local asset paths:

```sh
npm run build
```

Online builds use the COS public path configured in `.env.cos`:

```sh
npm run build:cos
npm run upload:cos
```

Build and upload in one command:

```sh
npm run deploy:cos
```

Before uploading for the first time, install COSCLI:

```sh
coscli --version
```

The upload script reads COS upload settings from `package.json`:

```json
{
  "cos": {
    "Mode": "SecretKey",
    "SecretID": "your-secret-id",
    "SecretKey": "your-secret-key",
    "SessionToken": "",
    "BucketName": "ap-ives-1304933815",
    "BucketEndpoint": "cos.ap-guangzhou.myqcloud.com",
    "BucketAlias": "ap-ives-1304933815",
    "AssetPrefix": "assets",
    "SourceDir": "dist/assets"
  }
}
```

Update `.env.cos` to change the online asset host:

```sh
VITE_PUBLIC_PATH=https://ap-ives-1304933815.cos.ap-guangzhou.myqcloud.com/
```

The Jenkins pipeline runs `npm run build:cos`, then uploads `dist/assets/` to
COS with `npm run upload:cos`. Make sure `coscli` is installed on the Jenkins
agent.
