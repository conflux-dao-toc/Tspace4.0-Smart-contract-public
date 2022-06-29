### 合约说明：
    部署的合约共有四个：
    1、NFT合约，contracts/art/*.sol （建议使用最新的2.0版本https://github.com/conflux-dao-toc/NFT2.0，
    详见https://forum.conflux.fun/t/conflux/15538 Conflux社区NFT标准规范及DEMO）
    2、交易合约，contracts/market/FixedExchangeV2.sol
    3、拍卖合约，contracts/market/EnglishExchange.sol
    4、usdt-cfx价格预言机
    其他合约为相关工具和依赖。
    
    交易合约，目前都使用"签名"模式而非"质押"模式。
     
    合约已使用conflux赞助特性。（测试时候未开启，需测试账户从水龙头领测试cfx。正式上线前取消掉注释即可）
    部分函数已有防重入判断。
    目前好像未禁止合约发起请求。（可能不需要禁止？）
    交易合约改手续费函数有时间锁，改手续费时间锁默认1天，手续费最大不超过0.3cfx
   
### 合约编译部署说明：

    一、先安装openzeppelin依赖库
    npm install @openzeppelin/contracts

    然后需要改两个地方如下：
    1、openzeppelin 中的 token/erc777 的 1820 合约中更改为这个: 
    IERC1820Registry constant internal _ERC1820_REGISTRY = IERC1820Registry(0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820);
    2、openzeppelin 中的 token/erc1155 合约中uri的函数需要加一个virtual关键字:
    function uri(uint256) external view overridereturns (string memory) {
        return _uri;
    }
    改为：
    function uri(uint256) external view override virtual returns (string memory) {
        return _uri;
    }

    二、编译
    方法1、cfxtruffle compile 这个比较快（斑）
    方法2、codevs插件solidity0.0.113编译。(chy)
    下载编译器https://github.com/ethereum/solc-bin/blob/gh-pages/bin/soljson-v0.6.9%2Bcommit.3e3065ac.js（需翻墙）。
    进入solidity设置，将默认编辑器改为localFile，将下载好的编译器本地路径填上（chy）
    在sol文件内右键，compile contract
    编译好的文件默认在bin\contracts\下面。
    
    三、部署
    方法一（斑）
    cfxtruffle migration --network [wtest] [--reset] 

    编译完再在studio部署
    
    方法二、（chy)
    conflux studio，选择测试网或主网，打开同一个合约项目文件夹，找到编译目录下的 *.json文件，打开找到"bytecode"和"deployedBytecode"。将他们的字节码前面加上0x。然后可以在json上右键点击Deploy(部署），稍等后会弹出成功和合约地址。

### 合约接口说明：usdt和cfx的价格预言机

	abi：/bin/art/PriceOracle2.json

	一、操作接口
        1.1 输入美金数额, 获取对应的cfx数额 
	(注意，输入返回都是整数，如果需要提高精度需前端注意）
	usdtToCfxPrice(
		uint256 usdt //usdt的数量
	)
	testnetUsdtToCfxPrice(
		uint256 usdt //usdt的数量
	)

### 合约接口说明: NFT铸造和读取

	abi：/build/TsArt.json	中的abi: []

   	一、操作接口
    1.1 转账NFT(标准NFT函数)
	safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    )

	1.2 批量转账NFT(标准NFT函数)
	safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )

	1.3 铸造发行NFT（有5cfx的费用，value = 5e18）
	mint(string _metadateUri)
	传入参数是metadate的字符串

	1.4 销毁NFT
	void (address owner, uint256 tokenId)
	传入参数是账户地址和NFT的id
	无返回值？

	二、查询接口
	2.1 查询某个id的NFT是否属于某个账户地址
	bool isTokenOwner(address _owner, uint256 _id)
	传入参数是地址和NFT的id
	返回值为布尔是否成功。

	2.2 获得某个id的NFT的所属账户地址
	address[] ownerOf(uint256 _id)
	传入参数为NFT的id
	返回值为地址的数组

	2.3 获得某个账户地址拥有的全部NFT的id数组
	uint256[] tokensOf(address _owner)
	传入参数为账户地址
	返回值为账户拥有的NFT的id的数组

	2.4 获得某个NFT的metadata(uri)字符串
	string uri(uint256 _id)
	传入参数为NFT的id
	返回值为对应NFT的uri的字符串
	返回的uri是合约的基础uri与nft的uri的连结字符串，形如：
	https://tspace.io/nft/{id:23,name:"ConFi",image:"ConFi/1123.png",description:"Super ConFi."}
	或者:
	Tspace{id:23,name:"ConFi",image:"ConFi/1123.png",description:"Super ConFi."}

	2.5 获得合约发行NFT总数量
	uint256 totalSupply()
	无传入参数
	返回值为数量

	三、日志操作
	3.1 铸造NFT日志
	event MintArt(address _onwer, uint256 _tokenId, string metedate);

	四、合约管理员操作
	4.1 设置铸造收费
	setPrice(uint256 _price)

	4.2 设置基础uri信息（会拼接到nft的uri的前面）
	setBaseUri(string memory _baseUri)

	4.3 平台发行/空投NFT
	addItem(address _to, string _metadateUri)
	传入参数为目标地址和uri信息
	
	4.4 合约提取铸造费到管理账户
	withdrawMain(uint256 _amount)	 
	

### 合约接口说明: EnglishExchange 英式拍卖（签名模式）

	abi：/bin/contracts/market/EnglishExchange.json	中的abi:
	
    一、操作接口
    1.1 新建订单
	bool creatOrder(Order order)
	传入参数是订单结构体order
	订单order这样传：[a,b,c,d,e,f,g,h]
	返回值为布尔是否成功。

	1.2 填写订单（买家提出报价）
	bool fillOrder(bytes32 _orderHash, Order order, bytes signature)
    传入参数是订单哈希值，订单结构体order，签名
	返回值为布尔是否成功。

	1.3 买家取消订单
	bool cancelOrder(bytes32 _orderHash, Order order)
    传入参数是订单哈希值，订单结构体order
	返回值为布尔是否成功
	
	1.4 卖家取消订单
	bool reverseOrder(Order order)
    传入参数是订单结构体order
	返回值为布尔是否成功

	二、查询接口
	2.1 查询订单
	orderInfo getOrderInfo(Order order)
    传入参数是订单结构体order
	返回值为订单信息结构体orderInfo

	2.2 计算订单结果
	fillResults calculateFillResults（Order order）
	传入参数是订单结构体order
	返回值为订单计算结果结构体

	2.3 获得订单起拍价
	uint256 getPricer(Order order)
	传入参数是订单结构体order
	返回值为订单起拍价

    三、日志接口
	3.1 订单创建日志
	event Created(
        bytes32 indexed orderHash, // Order's hash
        uint256 fee, // Fee order creator to pay
        address indexed feeRecipient,
        uint256 contractFee, // Fee order creator pay for contract
        address senderAddress, // DEX operator that submitted the order
        uint256 id,
        uint256 amount,
        address indexed owner,
        address assetAddress,
        address taker,
        address currencyAddress
    );
	3.2 订单填写日志（买家提出报价）
    // Fill event is emitted whenever an order is filled.
    event Fill(
        bytes32 indexed orderHash, // Order's hash
        uint256 fee, // Fee order creator to pay
        address indexed feeRecipient,
        uint256 contractFee, // Fee order creator pay for contract
        address senderAddress, // DEX operator that submitted the order
        uint256 id,
        uint256 amount,
        address indexed owner,
        address assetAddress,
        uint256 price,
        address taker,
        address currencyAddress
    );
	3.3 买家取消订单日志
    // Cancel event is emitted whenever an individual order is cancelled.
    event Cancel(
        bytes32 indexed orderHash,
        address indexed creator,
        address indexed feeRecipient,
        address assetAddress,
        address currencyAddress,
        address senderAddress
    );
	3.4 合约手续费改变日志
    // Contract fee parameters get updated
    event ContractFeeParamsUpdated(
        address indexed owner,
        uint256 feePercentage,
        address feeRecipient
    );
	3.5 卖家取消订单
    event ReverseOrder(
        bytes32 indexed orderHash, // Order's hash
        uint256 status
    );

	四、合约管理员接口
	4.1 设置交易手续费百分比和收款账户
	setContractFeeParams(
        uint256 _contractFeePercentage,
        address _contractFeeRecipient
    ) 

	4.2 设置英式拍卖的什么？
	setEnglishExchange(IExchange _iExchange)
	
### 合约接口说明: FixedExchange V2 (一口价，签名模式)

	abi：/bin/contracts/market/FixedExchangeV2.json	中的abi:

	关于签名的测试：
	前端使用签名代码
	Order memory传入值是这样 [ a,b,c,d,e,f .......]  数组性质  就是元组 tuple格式

	一、操作接口
    1.1 新建订单
	bool creatOrder(OrderFixed order)
	传入参数是订单结构体order
	订单order这样传：[a,b,c,d,e,f,g,h]
	返回值为布尔是否成功。

	1.2 填写订单（买家直接购买）
	bool fillOrder( OrderFixed order, bytes signature)
    传入参数是订单哈希值，订单结构体order，签名
	返回值为布尔是否成功。
	
	1.3 卖家取消订单
	bool reverseOrder(OrderFixed order)
    传入参数是订单结构体order
	返回值为布尔，取消是否成功

	二、查询接口
	
	2.1 查询订单信息
	orderInfo getOrderInfo(OrderFixed order)
    传入参数是订单结构体order
	返回值为订单信息结构体orderInfo

	2.2 计算订单结果
	fillResults calculateFillResults（OrderFixed order）
	传入参数是订单结构体order
	返回值为订单计算结果结构体

	2.3 获得订单价格
	uint256 getPricer(OrderFixed order)
	传入参数是订单结构体order
	返回值为订单价格

	2.4 查询订单哈希值
	bytes32 getFixedHash(OrderFixed order)
    传入参数是订单结构体order
	返回值为订单信息哈希值bytes32格式

    三、日志接口
	3.1 订单创建日志
	event Created(
        bytes32 indexed orderHash, // Order's hash
        uint256 fee, // Fee order creator to pay
        address indexed feeRecipient,
        uint256 contractFee, // Fee order creator pay for contract
        address senderAddress, // DEX operator that submitted the order
        uint256 id,
        uint256 amount,
        address indexed owner,
        address assetAddress,
        address taker,
        address currencyAddress
    );
    3.2 卖家取消订单日志
    event Reverse(
        bytes32 indexed orderHash, // Order's hash
        uint256 status
    );

	3.3 买家购买订单日志
    // Fill event is emitted whenever an order is filled.
    event Fill(
        bytes32 indexed orderHash, // Order's hash
        uint256 fee, // Fee order creator to pay
        address indexed feeRecipient,
        uint256 contractFee, // Fee order creator pay for contract
        address senderAddress, // DEX operator that submitted the order
        uint256 id,
        uint256 amount,
        address indexed owner,
        address assetAddress,
        uint256 price,
        address taker,
        address currencyAddress
    );
	3.4 合约更新手续费日志
    // Contract fee parameters get updated
    event ContractFeeParamsUpdated(
        address indexed owner,
        uint256 feePercentage,
        address feeRecipient
    );
	
	四、合约管理员接口
	4.1 设置交易手续费百分比和收款账户
	setContractFeeParams(
        uint256 _contractFeePercentage,
        address _contractFeeRecipient
    ) 

	4.2 设置另一个合约地址，防止同时下单拍卖和一口价
	setEnglishExchange(IExchange _iExchange)

### 合约接口说明：FixedExchange V1 (一口价，质押模式)（已停用，改用上方的V2）

	
	abi: /build/FixedExchange.json  中的abi: []
	
	前端：
	
	查询：
	获取我的订单:
	getMyList(
			address _owner // 买家
			)
	返回值：
	[1,2,3,4]  //一口价id 列表
	
	获取所有的订单
	getFixedInfoList()
	返回值：
	[1,2,3,4]  //一口价id 列表
	
	获取当前订单详情：
		fixedInfos(
					uint256 _fixedId //一口价id
					)
		返回值：
		uint256 fixedId;  			//一口价id
		address nft; 				//nft
		uint256 tokenId;			//nft的tokenId
		address seller;			//卖家
		address buyer;			//买家
		uint256 amount;			//数量
		address spendToken; 	//花费的代币（777）
		uint32 fixedStatus; 		//订单状态 0 on sell, 1 buy ,2 cancel
		uint256 startTime; 		//开始时间
		uint256 endTime; 		//结束时间
	
	操作：
	售卖nft，首先先调用nft的 setApprovalForAll(address operator, bool approved)  operator: 买卖合约，approved: true
	sell(
		address _nft,			//nft
		uint256 _tokenId, 		//nft的tokenId
            address _spendToken,  	//花费的代币（777） ，若为cfx，则填写 0x0000000000000000000000000000000000000000 新地址则需要转换下
            uint256 _amount,		//数量
            uint256 _endTime	 	//结束时间
            )
            
	买家购买nft
	buy(
		uint256 _fixedId, 		//一口价id
		uint256 _amount			//数量
		) 
		
	卖家撤销售卖
	reverse(
			uint256 _fixedId		//一口价id
			) 

	日志
	Sell(
	 	uint256 _fixedId, 		//一口价id
	 	address _seller, 			//卖家
	 	address _spendToken, 	//花费的代币（777）
	 	uint256 _amount, 		//数量
	 	address _nft, 			//nft
	 	uint256 _tokenId, 		//nft的tokenId
	 	uint256 _fixedStatus, 		//0 在售状态
		uint256 startTime, 		//开始时间
		uint256 endTime 		//结束时间
	 	);
	 	
	Buy(
		uint256 _fixedId,  		//一口价id
		address _buyer, 			//买家
		 address _spendToken,  	//花费的代币（777）
		 uint256 _amount, 		//数量
		 address _nft, 			//nft
		 uint256 _tokenId,  		//nft的tokenId
		 uint256 _fixedStatus 	//1 成交状态
		 );
	 
	 Reverse(
	 	uint256 _fixedId, 		//一口价id
	 	uint256 _fixedStatus 		// 2 撤销状态
	 );
	 
