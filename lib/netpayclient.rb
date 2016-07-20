require "netpayclient/version"

module Netpayclient
  require 'digest/sha1'
  require 'mcrypt'
  require 'iniparse'

  DES_KEY = 'SCUBEPGW'
  HASH_PAD = '0001ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff003021300906052b0e03021a05000414'

  @@private_key = {}

  def self.hex2bin(hexdata)
    [hexdata].pack "H*"
  end

  def self.padstr(src, len=256, chr='0', d='L')
    src.strip!
    case d
    when 'L'
      src.rjust(len, chr)
    else
      src.ljust(len, chr)
    end
  end

  def self.bin2int(bindata)
    self.bchexdec(bindata.unpack('H*'))
  end

  def self.bchexdec(hexdata)
    hexdata.to_i(16)
  end

  def self.bcdechex(decdata)
    decdata.to_s(16)
  end

  def self.sha1_128(string)
    hash = Digest::SHA1.hexdigest(string)
    sha_bin = self.hex2bin(hash)
    sha_pad = self.hex2bin(HASH_PAD)
    sha_pad + sha_bin
  end

  def self.mybcpowmod(num, pow, mod)
    num ** pow % mod
  end

  def self.rsa_encrypt(private_key,input)
    p = self.bin2int(private_key[:prime1])
    q = self.bin2int(private_key[:prime2])
    u = self.bin2int(private_key[:coefficient])
    dP	= self.bin2int(private_key[:prime_exponent1])
    dQ	= self.bin2int(private_key[:prime_exponent2])
    c	= self.bin2int(input)
    cp = c % p
    cq = c % q
    a = self.mybcpowmod(cp,dP,p)
    b = self.mybcpowmod(cq,dQ,q)
    if a > b
        result = a - b
    else
        result = b - a
        result = p - result
    end
    result = result % p
    result = result * u
    result = result % p
    result = result * q
    result = result + b
    ret = self.bcdechex(result)
    ret = self.padstr(ret).upcase
    ret.size == 256 ? ret : false
  end

  def self.rsa_decrypt(input)
    check = self.bchexdec(input)
    modulus = self.bin2int(@@private_key["modulus"])
    exponent = self.bchexdec("010001")
    result = self.mybcpowmod(check,exponent,modulus)
    rb = self.bcdechex(result)
    self.padstr(rb).upcase
  end

  def self.build_key(key)
    @@private_key.clear
    ret = false
    key_file = IniParse.parse(File.read(key))['NetPayClient']
    hex = ""
    if not key_file['MERID'].nil?
        ret = key_file['MERID']
        @@private_key[:MERID] = ret
        hex = key_file['prikeyS'][80...key_file['prikeyS'].size]
    elsif not key_file['PGID'].nil?
      ret = key_file['PGID']
      @@private_key[:PGID] = ret
      hex = key_file['pubkeyS'][48...key_file['pubkeyS'].size]
    else
      return ret
    end
    bin = self.hex2bin(hex)
    @@private_key[:modulus] = bin[0,128]
    iv = "\x00" * 8
    prime1 = bin[384,64]

    crypto = Mcrypt.new(:des, :cbc)
    crypto.key = DES_KEY
    crypto.iv = iv
    crypto.padding = :zeros
    enc = crypto.encrypt(prime1)
    @@private_key[:prime1] = enc
    prime2 = bin[448,64]
    enc = crypto.encrypt(prime2)
    @@private_key[:prime2] = enc
    prime_exponent1 = bin[512,64]
    enc = crypto.encrypt(prime_exponent1)
    @@private_key[:prime_exponent1] = enc
    prime_exponent2 = bin[576,64]
    enc = crypto.encrypt(prime_exponent2)
    @@private_key[:prime_exponent2] = enc
    coefficient = bin[640,64]
    enc = crypto.encrypt(coefficient)
    @@private_key[:coefficient] = enc
    return ret
  end

  def self.sign(msg)
    if not @@private_key.key?(:MERID)
      return false
    end
    hb = self.sha1_128(msg)
    return self.rsa_encrypt(@@private_key, hb)
  end

  def self.sign_order(merid,ordno,amount,curyid,transdate,transtype)
    return false if (merid.size!=15)
    return false if (ordno.size!=16)
    return false if (amount.size!=12)
    return false if (curyid.size!=3)
    return false if (transdate.size!=8)
    return false if (transtype.size!=4)
    plain = merid + ordno + amount + curyid + transdate + transtype
    return self.sign(plain)
  end

  def verify(plain,check)
    return false if not @@private_key.key?(:PGID)
    return false if check.size != 256
    hb = self.sha1_128(plain)
    hbhex = hb.unpack('H*').upcase
    rbhex = self.rsa_decrypt(check)
    return hbhex == rbhex ? true : false
  end

  def verify_trans_response(merid,ordno,amount,curyid,transdate,transtype,ordstatus,check)
    return false if (merid.size!=15)
    return false if (ordno.size!=16)
    return false if (amount.size!=12)
    return false if (curyid.size!=3)
    return false if (transdate.size!=8)
    return false if (transtype.size!=4)
    return false if (ordstatus.size!=4)
    return false if (check.size!=256)
    plain = merid + ordno + amount + curyid + transdate + transtype + ordstatus
    return self.verify(plain, check)
  end
end