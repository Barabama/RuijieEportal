# 福州大学锐捷校园网认证脚本

FZU Ruijie ePortal Web Authentication Tool

提供了基于Python和Bash的脚本，锐捷认证现在要求Post请求加密后的密码，RSA加密依赖`gmp`实现，
其中Python脚本空间要求更高，


## 使用说明

- Bash依赖`curl`、`sed`、`awk`、`libgmp-dev`。

```shell
# login
bash ./web_hust.sh $username $password

# logout
bash ./web_hust.sh logout 
```

- Python依赖`requests`、`gmpy2`。

```shell
# login
python main.py $username $password

# logout
python main.py logout
```

<a href="校园网路由器.md">基于OpenWRT路由器的校园网突破设备限制解决方案<a>

## 特别声明

- 本程序仅为自动化登录脚本，不涉及任何破解盗版信息。
- 仅供学习交流，严禁用于商业用途，请于24小时内删除。
- 禁止将本站资源进行任何形式的出售，产生的一切后果由侵权者自负！

## 参考文献

- [SWUOSA/ruijie-authentication: 西南大学校园网自动登录脚本，基于Python](https://github.com/SWUOSA/ruijie-authentication)
- [ehxu/Ruijie_JMU: 锐捷 ePortal Web 认证自动登录脚本（Linux & Windows）](https://github.com/ehxu/Ruijie_JMU)
- [callmeliwen/RuijiePortalLoginTool: 集美大学锐捷 ePortal Web 认证自动登录脚本](https://github.com/callmeliwen/RuijiePortalLoginTool)
