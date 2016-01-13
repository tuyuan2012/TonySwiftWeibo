//
//  StatusDAO.swift
//  DSWeibo
//
//  Created by xiaomage on 15/9/21.
//  Copyright © 2015年 小码哥. All rights reserved.
//

import UIKit

/// 数据访问层
class StatusDAO: NSObject {
    
    /// 清空过期的数据
    class  func cleanStatuses() {
        
//        let date = NSDate()
        let formatter = NSDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = NSLocale(localeIdentifier: "en")
        
        let date = NSDate(timeIntervalSinceNow: -60)
        let dateStr = formatter.stringFromDate(date)
//        print(dateStr)
        
        // 1.定义SQL语句
        let sql = "DELETE FROM T_Status WHERE createDate  <= '\(dateStr)';"
        
        // 2.执行SQL语句
        SQLiteManager.shareManager().dbQueue?.inDatabase({ (db) -> Void in
            db.executeUpdate(sql, withArgumentsInArray: nil)
        })
    }

    /// 加载微博数据
    class  func loadStatuses(since_id: Int, max_id: Int, finished: ([[String: AnyObject]]?, error: NSError?)->()) {
        
        // 1.从本地数据库中获取
        loadCacheStatuses(since_id, max_id: max_id) { (array) -> () in
            
            // 2.如果本地有, 直接返回
            if !array!.isEmpty
            {
                print("从数据库中获取")
                finished(array, error: nil)
                return
            }
            
            
            
            // 3.从网络获取
            let path = "2/statuses/home_timeline.json"
            var params = ["access_token": UserAccount.loadAccount()!.access_token!]
        
            // 下拉刷新
            if since_id > 0
            {
                params["since_id"] = "\(since_id)"
            }
            
            // 上拉刷新
            if max_id > 0
            {
                params["max_id"] = "\(max_id - 1)"
            }
            
            NetworkTools.shareNetworkTools().GET(path, parameters: params, success: { (_, JSON) -> Void in
                let array = JSON["statuses"] as! [[String : AnyObject]]
                // 4.将从网络获取的数据缓存起来
                cacheStatuses(array)
                
                // 5.返回获取到的数据
                finished(array, error: nil)
                
                StatusDAO.cacheStatuses(JSON["statuses"] as! [[String: AnyObject]])

                }) { (_, error) -> Void in
                    print(error)
                    finished(nil, error: error)
            }
        }
    }
    
    /// 从数据库中加载缓存数据
    class func loadCacheStatuses(since_id: Int, max_id: Int, finished: ([[String: AnyObject]]?)->()) {
        
        // 1.定义SQL语句
        var sql = "SELECT * FROM T_Status \n"
        if since_id > 0
        {
            sql += "WHERE statusId > \(since_id) \n"
        }else if max_id > 0
        {
            sql += "WHERE statusId < \(max_id) \n"
        }
        
        sql += "ORDER BY statusId DESC \n"
        sql += "LIMIT 20; \n"
        
        // 2.执行SQL语句
        SQLiteManager.shareManager().dbQueue?.inDatabase({ (db) -> Void in
            
            // 2.1查询数据
            // 返回字典数组的原因:通过网络获取返回的也是字典数组,
            // 让本地和网络返回的数据类型保持一致, 以便于我们后期处理
            var statuses = [[String: AnyObject]]()
            
            if let res =  db.executeQuery(sql, withArgumentsInArray: nil)
            {
                // 2.2遍历取出查询到的数据
                while res.next()
                {
                    // 1.取出数据库存储的一条微博字符串
                    let dictStr = res.stringForColumn("statusText") as String
                    // 2.将微博字符串转换为微博字典
                    let data = dictStr.dataUsingEncoding(NSUTF8StringEncoding)!
                    let dict = try! NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableContainers) as! [String: AnyObject]
                    statuses.append(dict)
                }
                
                // 3.返回数据
                finished(statuses)
                
            }
            
            // 3.返回数据
            finished(statuses)
            
        })
    }
    
    /// 缓存微博数据
    class func cacheStatuses(statuses: [[String: AnyObject]])
    {
        
        // 0. 准备数据
        let userId = UserAccount.loadAccount()!.uid!
        
        // 1.定义SQL语句
        let sql = "INSERT OR REPLACE INTO T_Status" +
            "(statusId, statusText, userId)" +
            "VALUES" +
            "(?, ?, ?);"
        
        // 2.执行SQL语句
        SQLiteManager.shareManager().dbQueue?.inTransaction({ (db, rollback) -> Void in
            
            for dict in statuses
            {
                let statusId = dict["id"]!
                // JSON -> 二进制 -> 字符串
                let data = try! NSJSONSerialization.dataWithJSONObject(dict, options: NSJSONWritingOptions.PrettyPrinted)
                let statusText = String(data: data, encoding: NSUTF8StringEncoding)!
                print(statusText)
                if !db.executeUpdate(sql, statusId, statusText, userId)
                {
                    // 如果插入数据失败, 就回滚
                    rollback.memory = true
                }
                
            }
        })
    }
}
