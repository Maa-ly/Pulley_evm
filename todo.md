## TOdo


## multiple pool
- big
- small


with the way things are going i dont like the profit distribution and handling
okay so we will have different strategies depending on what users can afford, si un the clonePulleytrade we will clone treades , also in the PultradingPool, it should be done in a way that the yield will be shared fairly for everyone
so before someone deposits there should be is there an ongoing trade period check, if yes then we revert as you cant join during ongoing peiods, each personson contribution is tracked and their extenmated loss or profit can be calculated. so whe thereshold is reacher a period is created right and then the funds are sent to the controller the controller creats a request for he ai trader and stores all import info then send the funds to the ai-traer wallet 15 85 15 or isnurance and 85 for trades. the ai wallet works for that period and once that peipd is over reports profit or loss (we are using cfd trading and it will reflect loss or profit directly in the ais wallet) we use this understand to check for profit for that period.
flow eg
pool threshold is 200
user1 join trading pool -- deposits 50 usdc --- threshold hasnt been reached so peiod wont be started - gets minted pool tokens.
user2 joins trading pool --  deposits 100 usdc --- threshold hasnt been reached so peiod wont be started - gets minted pool tokens.
user1 join trading pool -- deposits 50 usdc --- threshold hasnt been reached so peiod wont be started - gets minted pool tokens.

now threshold has been reached and trading peiod fro that asset will start, new users cant join since tarding has staryed

next

funds get sent to the pulleycontroller
controller splits 15% 85%, creates isnurance for that particular trading pool and sends the 85% to the ai wallet () after ai wallets closes the position, we ccheck for profit or loss(we are using cfd trading and it will reflect loss or profit directly in the ais wallet) so the controller call that particular asset for the trading and cehcks for profit or loss, if it made a profot it shares it according 10% for insurance and 80% for those theres during the period. they can deceide to renter the funds in other peiod or withdraw




so the trading pool, wallet pulleycointroller should have like an initializer so we can iniaze it easy and set all things needed, like threshold etc, 
also make an error lib or something for all errors and event lib too and dtattypes lib.

each clone of pool should use 3 assets, native asset for the deployed chain(when i say this i dont mean create a lst of chain, when msg.value > zero we just say othis person want to use ative chain currency), pulleyToken and anyother asset set during.
note all these assets will have their peirods each and total stupply aculculated differentkly. write test to test everything, unit tests abd intergration and make sure they pass
 the trdaing pool each will have cloned conttroller an a clone wallet address. and from all the contract replace the dtata errorr events and create event error and dtata type libs to call from , replace in each contract
 do not set default vault names or threshold lets the person clone speiy all those details.

 also  the 15% for insurance should be a backup fund the pool get when they get a loss, i mean for that peiod, so that peiod who deposited that amount will get the inurance and will be slip with everyone during that peiods based on the shares

 so struture

 clone (clones a new trading pool with specfied infomation thereshold (clones wallet and controller))

 users enter trading pool --- period starts --- funds are sent to controller -- cntroler slips 15% for insurance for that period and 85% trading (it rewrds this tradeAi) and send the funds of the asse to the ai wallet(cfd profitor loss shows in account) controller check traderequest.deposit for that asset and period nad check it agsisnt the wallets totally supply for that asset if profit it distributes to the trading people and shares to the people for thatpeople based on shares, if loss pool get nother but we send pulltoken(the insurance for that perod and slip to the perood people based on shares) -- so eevrything is like a communication channel

 do not creat new files other than what i have told  you, work with the ones already there and implenment the fix 